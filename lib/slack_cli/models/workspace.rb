# frozen_string_literal: true

module SlackCli
  module Models
    Workspace = Data.define(:name, :token, :cookie) do
      def initialize(name:, token:, cookie: nil)
        super(name: name.to_s.freeze, token: token.to_s.freeze, cookie: cookie&.freeze)
      end

      def xoxc? = token.start_with?("xoxc-")
      def xoxb? = token.start_with?("xoxb-")
      def xoxp? = token.start_with?("xoxp-")

      def to_s = name

      def headers
        h = {
          "Authorization" => "Bearer #{token}",
          "Content-Type" => "application/json; charset=utf-8"
        }
        h["Cookie"] = "d=#{cookie}" if cookie
        h
      end
    end
  end
end
