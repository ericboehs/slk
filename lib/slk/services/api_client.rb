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
      attr_accessor :on_request, :on_response

      def initialize
        @call_count = 0
        @on_request = nil
        @on_response = nil
        @http_cache = {}
      end

      # Close all cached HTTP connections
      def close
        @http_cache.each_value { |http| safe_close(http) }
        @http_cache.clear
      end

      def post(workspace, method, params = {})
        execute_request(method) do |uri, http|
          request = Net::HTTP::Post.new(uri)
          workspace.headers.each { |k, v| request[k] = v }
          request.body = JSON.generate(params) unless params.empty?
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
        execute_request(method) do |uri, http|
          request = Net::HTTP::Post.new(uri)
          apply_auth_headers(request, workspace)
          request.set_form_data(params)
          http.request(request)
        end
      end

      private

      def safe_close(http)
        http.finish if http.started?
      rescue IOError
        # Connection already closed
      end

      def execute_request(method, query_params = nil)
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")
        uri.query = URI.encode_www_form(query_params) if query_params&.any?

        http = get_http(uri)
        response = yield(uri, http)
        log_response(method, response)
        handle_response(response, method)
      rescue *NETWORK_ERRORS => e
        raise ApiError, "Network error: #{e.message}"
      end

      def apply_auth_headers(request, workspace)
        request['Authorization'] = workspace.headers['Authorization']
        request['Cookie'] = workspace.headers['Cookie'] if workspace.headers['Cookie']
      end

      def log_request(method)
        @call_count += 1
        @on_request&.call(method, @call_count)
      end

      def log_response(method, response)
        return unless @on_response

        headers = {
          'X-RateLimit-Limit' => response['X-RateLimit-Limit'],
          'X-RateLimit-Remaining' => response['X-RateLimit-Remaining'],
          'X-RateLimit-Reset' => response['X-RateLimit-Reset'],
          'Retry-After' => response['Retry-After']
        }.compact

        @on_response.call(method, response.code, headers)
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
        when Net::HTTPUnauthorized then raise ApiError, 'Invalid token or session expired'
        when Net::HTTPTooManyRequests then handle_rate_limit(response)
        else raise ApiError, "HTTP #{response.code}: #{response.message}"
        end
      end

      def handle_rate_limit(response)
        retry_after = response['Retry-After']
        if retry_after
          raise ApiError, "Rate limited - retry after #{retry_after} seconds"
        else
          raise ApiError, 'Rate limited - please wait and try again'
        end
      end

      def parse_success_response(response)
        result = JSON.parse(response.body)
        raise ApiError, result['error'] || 'Unknown error' unless result['ok']

        result
      rescue JSON::ParserError
        raise ApiError, 'Invalid JSON response from Slack API'
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
