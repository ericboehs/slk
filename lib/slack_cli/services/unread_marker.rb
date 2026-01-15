# frozen_string_literal: true

module SlackCli
  module Services
    # Handles batch marking of unreads as read
    class UnreadMarker
      def initialize(conversations_api:, threads_api:, client_api:, users_api:, on_debug: nil)
        @conversations = conversations_api
        @threads = threads_api
        @client = client_api
        @users = users_api
        @on_debug = on_debug
      end

      # Mark all unreads in a workspace, return counts
      # @param options [Hash] :muted - include muted channels
      # @return [Hash] { dms: count, channels: count, threads: count }
      def mark_all(options: {})
        counts = @client.counts

        {
          dms: mark_dms(counts['ims'] || []),
          channels: mark_channels(counts['channels'] || [], muted: options[:muted]),
          threads: mark_threads
        }
      end

      # Mark a single channel as read
      # @param channel_id [String] Channel ID
      # @return [Boolean] true if marked successfully
      def mark_single_channel(channel_id)
        mark_conversation(channel_id)
      end

      private

      def mark_dms(ims)
        count = 0
        ims.each do |im|
          next unless im['has_unreads']

          count += 1 if mark_conversation(im['id'])
        end
        count
      end

      def mark_channels(channels, muted: false)
        muted_ids = muted ? [] : @users.muted_channels
        count = 0

        channels.each do |channel|
          next unless channel['has_unreads']
          next if !muted && muted_ids.include?(channel['id'])

          count += 1 if mark_conversation(channel['id'])
        end
        count
      end

      def mark_conversation(channel_id)
        history = @conversations.history(channel: channel_id, limit: 1)
        messages = history['messages']
        return false unless messages&.any?

        @conversations.mark(channel: channel_id, timestamp: messages.first['ts'])
        true
      rescue ApiError => e
        @on_debug&.call("Could not mark #{channel_id}: #{e.message}")
        false
      end

      def mark_threads
        response = @threads.get_view(limit: 50)
        return 0 unless response['ok']

        count = 0
        (response['threads'] || []).each do |thread|
          count += 1 if mark_thread(thread)
        end
        count
      end

      def mark_thread(thread)
        unread_replies = thread['unread_replies'] || []
        return false if unread_replies.empty?

        call_mark_thread(thread, unread_replies)
      end

      def call_mark_thread(thread, unread_replies)
        root_msg = thread['root_msg'] || {}
        @threads.mark(channel: root_msg['channel'], thread_ts: root_msg['thread_ts'],
                      timestamp: unread_replies.map { |r| r['ts'] }.max)
        true
      rescue ApiError => e
        @on_debug&.call("Could not mark thread #{root_msg['thread_ts']} in #{root_msg['channel']}: #{e.message}")
        false
      end
    end
  end
end
