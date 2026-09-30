# frozen_string_literal: true

module Slk
  module Services
    # Subscribes to or unsubscribes from a thread without posting in it.
    #
    # Slack wants the thread's parent timestamp plus a last-read marker. A
    # permalink can point at any reply, so the parent is looked up first and
    # its latest reply becomes the marker: what is already there counts as
    # read, and only replies posted after subscribing show up as unread.
    class ThreadSubscription
      Result = Data.define(:channel_id, :thread_ts, :last_read)

      def initialize(conversations_api:, threads_api:)
        @conversations = conversations_api
        @threads = threads_api
      end

      # @param channel_id [String] Channel ID
      # @param timestamp [String] Timestamp of the parent or any reply
      # @return [Result]
      def subscribe(channel_id:, timestamp:)
        change(:subscribe, channel_id, timestamp)
      end

      # @param channel_id [String] Channel ID
      # @param timestamp [String] Timestamp of the parent or any reply
      # @return [Result]
      def unsubscribe(channel_id:, timestamp:)
        change(:unsubscribe, channel_id, timestamp)
      end

      private

      def change(action, channel_id, timestamp)
        result = locate(channel_id, timestamp)
        @threads.public_send(action, channel: channel_id, thread_ts: result.thread_ts, last_read: result.last_read)
        result
      end

      def locate(channel_id, timestamp)
        message = first_message(channel_id, timestamp)
        thread_ts = message['thread_ts'] || message['ts'] || timestamp
        # Pointed at a reply: only the parent carries latest_reply.
        message = first_message(channel_id, thread_ts) if message['ts'] && message['ts'] != thread_ts

        Result.new(channel_id: channel_id, thread_ts: thread_ts, last_read: message['latest_reply'] || thread_ts)
      end

      def first_message(channel_id, timestamp)
        response = @conversations.replies(channel: channel_id, timestamp: timestamp, limit: 1)
        message = (response['messages'] || []).first
        raise ApiError.new('thread_not_found', code: :thread_not_found) unless message

        message
      end
    end
  end
end
