# frozen_string_literal: true

module Slk
  module Api
    # Wrapper for Slack thread subscription API endpoints
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
      # @param timestamp [String] Latest reply timestamp to mark as read
      def mark(channel:, thread_ts:, timestamp:)
        @api.post_form(@workspace, 'subscriptions.thread.mark', {
                         channel: channel,
                         thread_ts: thread_ts,
                         ts: timestamp
                       })
      end

      # Subscribe to (follow) a thread so new replies land in the Threads view
      # Requires a session (xoxc) token; this is an undocumented client endpoint.
      # @param channel [String] Channel ID
      # @param thread_ts [String] Thread parent timestamp
      # @param last_read [String] Latest reply timestamp to treat as already read
      def subscribe(channel:, thread_ts:, last_read:)
        @api.post_form(@workspace, 'subscriptions.thread.add', subscription_params(channel, thread_ts, last_read))
      end

      # Unsubscribe from (unfollow) a thread
      # @param channel [String] Channel ID
      # @param thread_ts [String] Thread parent timestamp
      # @param last_read [String] Latest reply timestamp to treat as already read
      def unsubscribe(channel:, thread_ts:, last_read:)
        @api.post_form(@workspace, 'subscriptions.thread.remove', subscription_params(channel, thread_ts, last_read))
      end

      # Check whether you are subscribed to a thread
      # @param channel [String] Channel ID
      # @param thread_ts [String] Thread parent timestamp
      def get(channel:, thread_ts:)
        @api.post_form(@workspace, 'subscriptions.thread.get', { channel: channel, thread_ts: thread_ts })
      end

      # Get unread thread count
      # @return [Integer] Number of unread thread replies
      def unread_count
        response = get_view(limit: 1)
        response['total_unread_replies'] || 0
      end

      # Check if there are unread threads
      # @return [Boolean]
      def unreads?
        unread_count.positive?
      end

      private

      def subscription_params(channel, thread_ts, last_read)
        { channel: channel, thread_ts: thread_ts, last_read: last_read }
      end
    end
  end
end
