# frozen_string_literal: true

module SlackCli
  module Services
    # HTTP client for Slack API with connection pooling
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
      attr_accessor :on_request

      def initialize
        @call_count = 0
        @on_request = nil
        @http_cache = {}
      end

      # Close all cached HTTP connections
      def close
        @http_cache.each_value do |http|
          http.finish if http.started?
        rescue IOError
          # Connection already closed
        end
        @http_cache.clear
      end

      def post(workspace, method, params = {})
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")

        http = get_http(uri)

        request = Net::HTTP::Post.new(uri)
        workspace.headers.each { |k, v| request[k] = v }
        request.body = JSON.generate(params) unless params.empty?

        response = http.request(request)
        handle_response(response, method)
      rescue *NETWORK_ERRORS => e
        raise ApiError, "Network error: #{e.message}"
      end

      def get(workspace, method, params = {})
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")
        uri.query = URI.encode_www_form(params) unless params.empty?

        http = get_http(uri)

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = workspace.headers['Authorization']
        request['Cookie'] = workspace.headers['Cookie'] if workspace.headers['Cookie']

        response = http.request(request)
        handle_response(response, method)
      rescue *NETWORK_ERRORS => e
        raise ApiError, "Network error: #{e.message}"
      end

      # Form-encoded POST (some Slack endpoints require this)
      def post_form(workspace, method, params = {})
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")

        http = get_http(uri)

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = workspace.headers['Authorization']
        request['Cookie'] = workspace.headers['Cookie'] if workspace.headers['Cookie']
        request.set_form_data(params)

        response = http.request(request)
        handle_response(response, method)
      rescue *NETWORK_ERRORS => e
        raise ApiError, "Network error: #{e.message}"
      end

      private

      def log_request(method)
        @call_count += 1
        @on_request&.call(method, @call_count)
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
        when Net::HTTPSuccess
          result = JSON.parse(response.body)
          raise ApiError, result['error'] || 'Unknown error' unless result['ok']

          result
        when Net::HTTPUnauthorized
          raise ApiError, 'Invalid token or session expired'
        when Net::HTTPTooManyRequests
          raise ApiError, 'Rate limited - please wait and try again'
        else
          raise ApiError, "HTTP #{response.code}: #{response.message}"
        end
      rescue JSON::ParserError
        raise ApiError, 'Invalid JSON response from Slack API'
      end
    end
  end
end
