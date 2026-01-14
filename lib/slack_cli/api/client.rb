# frozen_string_literal: true

module SlackCli
  module Api
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

        channel_count = (response['channels'] || []).sum { |c| c['mention_count'] || 0 }
        dm_count = (response['ims'] || []).sum { |d| d['mention_count'] || 0 }
        mpim_count = (response['mpims'] || []).sum { |m| m['mention_count'] || 0 }

        channel_count + dm_count + mpim_count
      end
    end
  end
end
