# frozen_string_literal: true

module SlackCli
  module Api
    class Bots
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      # Look up bot information by ID
      # @param bot_id [String] Bot ID starting with "B"
      # @return [Hash, nil] Bot info hash or nil if not found
      def info(bot_id)
        response = @api.post_form(@workspace, "bots.info", { bot: bot_id })
        response["bot"] if response["ok"]
      rescue ApiError
        nil
      end

      # Get bot name by ID
      # @param bot_id [String] Bot ID starting with "B"
      # @return [String, nil] Bot name or nil if not found
      def get_name(bot_id)
        bot = info(bot_id)
        bot&.dig("name")
      end
    end
  end
end
