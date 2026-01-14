# frozen_string_literal: true

module SlackCli
  module Api
    class Threads
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      # Get unread threads
      # @param limit [Integer] Max threads to return
      # @return [Hash] Response with threads and total_unread_replies
      def get_view(limit: 20)
        @api.post(@workspace, 'subscriptions.thread.getView', { limit: limit })
      end

      # Mark a thread as read
      # @param channel [String] Channel ID
      # @param thread_ts [String] Thread timestamp
      # @param ts [String] Latest reply timestamp to mark as read
      def mark(channel:, thread_ts:, ts:)
        @api.post_form(@workspace, 'subscriptions.thread.mark', {
                         channel: channel,
                         thread_ts: thread_ts,
                         ts: ts
                       })
      end

      # Get unread thread count
      # @return [Integer] Number of unread thread replies
      def unread_count
        response = get_view(limit: 1)
        response['total_unread_replies'] || 0
      end

      # Check if there are unread threads
      # @return [Boolean]
      def has_unreads?
        unread_count.positive?
      end
    end
  end
end
