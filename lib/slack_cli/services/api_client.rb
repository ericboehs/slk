# frozen_string_literal: true

module SlackCli
  module Services
    class ApiClient
      BASE_URL = ENV.fetch("SLACK_API_BASE", "https://slack.com/api")

      attr_reader :call_count
      attr_accessor :on_request

      def initialize
        @call_count = 0
        @on_request = nil
      end

      def post(workspace, method, params = {})
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")

        http = Net::HTTP.new(uri.host, uri.port)
        configure_ssl(http, uri)

        request = Net::HTTP::Post.new(uri)
        workspace.headers.each { |k, v| request[k] = v }
        request.body = JSON.generate(params) unless params.empty?

        response = http.request(request)
        handle_response(response, method)
      end

      def get(workspace, method, params = {})
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")
        uri.query = URI.encode_www_form(params) unless params.empty?

        http = Net::HTTP.new(uri.host, uri.port)
        configure_ssl(http, uri)

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = workspace.headers["Authorization"]
        request["Cookie"] = workspace.headers["Cookie"] if workspace.headers["Cookie"]

        response = http.request(request)
        handle_response(response, method)
      end

      # Form-encoded POST (some Slack endpoints require this)
      def post_form(workspace, method, params = {})
        log_request(method)
        uri = URI("#{BASE_URL}/#{method}")

        http = Net::HTTP.new(uri.host, uri.port)
        configure_ssl(http, uri)

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = workspace.headers["Authorization"]
        request["Cookie"] = workspace.headers["Cookie"] if workspace.headers["Cookie"]
        request.set_form_data(params)

        response = http.request(request)
        handle_response(response, method)
      end

      private

      def log_request(method)
        @call_count += 1
        @on_request&.call(method, @call_count)
      end

      def configure_ssl(http, uri)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        return unless http.use_ssl?

        # Use system certificate store and disable CRL checking
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = OpenSSL::X509::Store.new
        http.cert_store.set_default_paths
      end

      def handle_response(response, method)
        case response
        when Net::HTTPSuccess
          result = JSON.parse(response.body)
          raise ApiError, result["error"] || "Unknown error" unless result["ok"]

          result
        when Net::HTTPUnauthorized
          raise ApiError, "Invalid token or session expired"
        when Net::HTTPTooManyRequests
          raise ApiError, "Rate limited - please wait and try again"
        else
          raise ApiError, "HTTP #{response.code}: #{response.message}"
        end
      rescue JSON::ParserError
        raise ApiError, "Invalid JSON response from Slack API"
      end
    end
  end
end
