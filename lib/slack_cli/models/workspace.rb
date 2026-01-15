# frozen_string_literal: true

module SlackCli
  module Models
    # Valid token prefixes for Slack tokens
    VALID_TOKEN_PREFIXES = %w[xoxb- xoxc- xoxp-].freeze

    Workspace = Data.define(:name, :token, :cookie) do
      def initialize(name:, token:, cookie: nil)
        name_str = name.to_s.strip
        token_str = token.to_s
        cookie_str = cookie&.to_s

        # Validate name is not empty and doesn't contain path separators
        raise ArgumentError, 'workspace name cannot be empty' if name_str.empty?
        raise ArgumentError, 'workspace name contains invalid characters' if name_str.match?(%r{[/\\]})

        # Validate token format
        unless VALID_TOKEN_PREFIXES.any? { |prefix| token_str.start_with?(prefix) }
          raise ArgumentError, 'invalid token format (must start with xoxb-, xoxc-, or xoxp-)'
        end

        # xoxc tokens require a cookie
        if token_str.start_with?('xoxc-') && (cookie_str.nil? || cookie_str.strip.empty?)
          raise ArgumentError, 'xoxc tokens require a cookie'
        end

        # Validate cookie doesn't contain newlines (HTTP header injection prevention)
        raise ArgumentError, 'cookie cannot contain newlines' if cookie_str&.match?(/[\r\n]/)

        super(name: name_str.freeze, token: token_str.freeze, cookie: cookie_str&.freeze)
      end

      def xoxc? = token.start_with?('xoxc-')
      def xoxb? = token.start_with?('xoxb-')
      def xoxp? = token.start_with?('xoxp-')

      def to_s = name

      def headers
        h = {
          'Authorization' => "Bearer #{token}",
          'Content-Type' => 'application/json; charset=utf-8'
        }
        h['Cookie'] = "d=#{cookie}" if cookie
        h
      end
    end
  end
end
