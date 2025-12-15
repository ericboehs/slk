# frozen_string_literal: true

module SlackCli
  module Api
    class Emoji
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def list
        @api.post(@workspace, "emoji.list")
      end

      def custom_emoji
        response = list
        response["emoji"] || {}
      end
    end
  end
end
