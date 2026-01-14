# frozen_string_literal: true

module SlackCli
  module Api
    # Wrapper for Slack usergroups.list API endpoint
    class Usergroups
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def list
        @api.post(@workspace, 'usergroups.list')
      end

      def get_handle(subteam_id)
        response = list
        return nil unless response['ok']

        usergroups = response['usergroups'] || []
        group = usergroups.find { |g| g['id'] == subteam_id }
        group&.dig('handle')
      end
    end
  end
end
