# frozen_string_literal: true

module SlackCli
  module Api
    class Activity
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def feed(limit: 50, types: 'message_reaction', cursor: nil)
        params = {
          mode: 'chrono_reads_and_unreads',
          limit: limit.to_s,
          types: types,
          archive_only: 'false',
          snooze_only: 'false',
          unread_only: 'false',
          priority_only: 'false',
          is_activity_inbox: 'false'
        }
        params[:cursor] = cursor if cursor

        @api.post_form(@workspace, 'activity.feed', params)
      end
    end
  end
end
