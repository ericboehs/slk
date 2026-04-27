# frozen_string_literal: true

module Slk
  module Services
    # HTTP client for Slack API with connection pooling
    # rubocop:disable Metrics/ClassLength
    class ApiClient
      BASE_URL = ENV.fetch('SLACK_API_BASE', 'https://slack.com/api')

      # Network errors that should be wrapped in ApiError
      NETWORK_ERRORS = [
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH,
        Net::OpenTimeout,
        Net::ReadTimeout,
        OpenSSL::SSL::SSLError
      ].freeze

      attr_reader :call_count
      attr_accessor :on_request, :on_response, :on_request_body, :on_response_body

      def initialize
        @call_count = 0
        @on_request = nil
        @on_response = nil
        @on_request_body = nil
        @on_response_body = nil
        @http_cache = {}
        @rate_resets = {}
      end

      # Close all cached HTTP connections
      def close
        @http_cache.each_value { |http| safe_close(http) }
        @http_cache.clear
      end

      def post(workspace, method, params = {})
        body = params.empty? ? nil : JSON.generate(params)
        execute_request(method, body: body) do |uri, http|
          request = Net::HTTP::Post.new(uri)
          workspace.headers.each { |k, v| request[k] = v }
          request.body = body
          http.request(request)
        end
      end

      def get(workspace, method, params = {})
        execute_request(method, params) do |uri, http|
          request = Net::HTTP::Get.new(uri)
          apply_auth_headers(request, workspace)
          http.request(request)
        end
      end

      # Form-encoded POST (some Slack endpoints require this)
      def post_form(workspace, method, params = {})
        body = params.empty? ? nil : URI.encode_www_form(params)
        execute_request(method, body: body) do |uri, http|
          request = Net::HTTP::Post.new(uri)
          apply_auth_headers(request, workspace)
          request.set_form_data(params) unless params.empty?
          http.request(request)
        end
      end

      private

      def safe_close(http)
        http.finish if http.started?
      rescue IOError
        # Connection already closed - this is expected, not an error
      end

      def execute_request(method, query_params = nil, body: nil, &)
        attempt_request(method, query_params, body: body, retried: false, &)
      rescue *NETWORK_ERRORS => e
        raise ApiError.new("Network error: #{e.message}", code: :network_error)
      end

      def attempt_request(method, query_params, body:, retried:, &)
        send_one_request(method, query_params, body: body, &)
      rescue RateLimitError => e
        wait = wait_for(e)
        raise e if retried || wait.nil?

        announce_wait(method, wait)
        sleep(wait)
        attempt_request(method, query_params, body: body, retried: true, &)
      end

      def send_one_request(method, query_params, body:, &)
        await_reset(method)
        log_request(method)
        log_request_body(method, body)
        uri = build_uri(method, query_params)
        response, elapsed_ms = timed_request(uri, &)
        track_rate_limit(method, response)
        log_response(method, response, elapsed_ms)
        log_response_body(method, response.body)
        handle_response(response, method)
      end

      def wait_for(error)
        max = ENV.fetch('SLK_MAX_RETRY_AFTER', '60').to_i
        seconds = error.retry_after || ENV.fetch('SLK_DEFAULT_RETRY_AFTER', '30').to_i
        return nil unless seconds.positive? && seconds <= max

        seconds
      end

      def announce_wait(method, seconds)
        @on_response&.call(method, 'rate-wait', { 'sleep_seconds' => seconds })
      end

      # Predictive throttle: when X-RateLimit-Remaining hits 0, sleep until
      # X-RateLimit-Reset before issuing the next call to that method.
      def track_rate_limit(method, response)
        remaining = response['X-RateLimit-Remaining']&.to_i
        reset = response['X-RateLimit-Reset']&.to_i
        @rate_resets[method] = reset if remaining&.zero? && reset&.positive?
      end

      def await_reset(method)
        reset = @rate_resets[method] or return
        wait = reset - Time.now.to_i
        return @rate_resets.delete(method) if wait <= 0

        max = ENV.fetch('SLK_MAX_RETRY_AFTER', '60').to_i
        return if wait > max

        announce_wait(method, wait)
        sleep(wait)
        @rate_resets.delete(method)
      end

      def build_uri(method, query_params)
        uri = URI("#{BASE_URL}/#{method}")
        uri.query = URI.encode_www_form(query_params) if query_params&.any?
        uri
      end

      def timed_request(uri)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        http = get_http(uri)
        response = yield(uri, http)
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)
        [response, elapsed_ms]
      end

      def apply_auth_headers(request, workspace)
        request['Authorization'] = workspace.headers['Authorization']
        request['Cookie'] = workspace.headers['Cookie'] if workspace.headers['Cookie']
      end

      def log_request(method)
        @call_count += 1
        @on_request&.call(method, @call_count)
      end

      def log_request_body(method, body)
        @on_request_body&.call(method, body) if body
      end

      def log_response(method, response, elapsed_ms)
        return unless @on_response

        headers = {
          'elapsed_ms' => elapsed_ms,
          'X-Slack-Req-Id' => response['X-Slack-Req-Id'],
          'X-RateLimit-Limit' => response['X-RateLimit-Limit'],
          'X-RateLimit-Remaining' => response['X-RateLimit-Remaining'],
          'X-RateLimit-Reset' => response['X-RateLimit-Reset'],
          'Retry-After' => response['Retry-After']
        }.compact

        @on_response.call(method, response.code, headers)
      end

      def log_response_body(method, body)
        @on_response_body&.call(method, body) if body
      end

      # Get or create a persistent HTTP connection for the given URI
      def get_http(uri)
        key = "#{uri.host}:#{uri.port}"
        cached = @http_cache[key]

        # Return cached connection if it's still active
        return cached if cached&.started?

        # Create new connection
        http = Net::HTTP.new(uri.host, uri.port)
        configure_ssl(http, uri)
        http.start

        @http_cache[key] = http
        http
      end

      def configure_ssl(http, uri)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 30
        http.keep_alive_timeout = 30

        return unless http.use_ssl?

        # Use system certificate store for SSL verification
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = OpenSSL::X509::Store.new
        http.cert_store.set_default_paths
      end

      def handle_response(response, _method)
        case response
        when Net::HTTPSuccess then parse_success_response(response)
        when Net::HTTPUnauthorized
          raise ApiError.new('Invalid token or session expired', code: :unauthorized)
        when Net::HTTPTooManyRequests then handle_rate_limit(response)
        else raise ApiError.new("HTTP #{response.code}: #{response.message}", code: :http_error)
        end
      end

      def handle_rate_limit(response)
        retry_after = response['Retry-After']&.to_i
        message = retry_after ? "Rate limited — retry after #{retry_after}s" : 'Rate limited — please wait'
        raise RateLimitError.new(message, retry_after: retry_after)
      end

      def parse_success_response(response)
        result = JSON.parse(response.body)
        raise_rate_limit(response) if result['error'] == 'ratelimited'
        unless result['ok']
          message = result['error'] || 'Unknown error'
          raise ApiError.new(message, code: message.to_sym)
        end

        result
      rescue JSON::ParserError
        raise ApiError.new('Invalid JSON response from Slack API', code: :invalid_json)
      end

      def raise_rate_limit(response)
        retry_after = response['Retry-After']&.to_i
        message = if retry_after
                    "Rate limited by Slack — retry after #{retry_after}s"
                  else
                    'Rate limited by Slack — wait a minute and try again'
                  end
        raise RateLimitError.new(message, retry_after: retry_after)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
