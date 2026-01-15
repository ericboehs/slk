# frozen_string_literal: true

module SlackCli
  module Api
    # Wrapper for the Slack activity.feed API endpoint
    class Activity
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def feed(limit: 50, types: nil, cursor: nil, mode: 'priority_reads_and_unreads_v1')
        params = build_feed_params(mode, limit)
        params[:types] = types if types
        params[:cursor] = cursor if cursor
        @api.post_form(@workspace, 'activity.feed', params)
      end

      private

      def build_feed_params(mode, limit)
        { mode: mode, limit: limit.to_s, archive_only: 'false', snooze_only: 'false',
          unread_only: 'false', priority_only: 'false', is_activity_inbox: 'false' }
      end
    end
  end
end
