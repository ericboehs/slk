# frozen_string_literal: true

module SlackCli
  module Api
    # Wrapper for Slack client.counts and auth.test API endpoints
    class Client
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def counts
        @api.post(@workspace, 'client.counts')
      end

      def auth_test
        @api.post(@workspace, 'auth.test')
      end

      def team_id
        @team_id ||= auth_test['team_id']
      end

      def unread_channels
        response = counts
        channels = response['channels'] || []

        channels.select { |ch| (ch['mention_count'] || 0).positive? || ch['has_unreads'] }
      end

      def unread_dms
        response = counts
        dms = response['ims'] || []
        mpims = response['mpims'] || []

        (dms + mpims).select { |dm| (dm['mention_count'] || 0).positive? || dm['has_unreads'] }
      end

      def total_unread_count
        response = counts
        sum_mentions(response, 'channels') + sum_mentions(response, 'ims') + sum_mentions(response, 'mpims')
      end

      private

      def sum_mentions(response, key)
        (response[key] || []).sum { |item| item['mention_count'] || 0 }
      end
    end
  end
end
