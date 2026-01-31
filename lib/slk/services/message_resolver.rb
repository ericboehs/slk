# frozen_string_literal: true

module Slk
  module Services
    # Resolves and fetches individual messages by timestamp from channels
    # Used by activity feed, saved items, and other features that need to
    # fetch message content by ts.
    class MessageResolver
      def initialize(conversations_api:, on_debug: nil)
        @api = conversations_api
        @on_debug = on_debug
      end

      # Fetch a single message by its timestamp from a channel
      # @param channel_id [String] The channel ID
      # @param message_ts [String] The message timestamp
      # @return [Hash, nil] The message data or nil if not found
      def fetch_by_ts(channel_id, message_ts)
        response = fetch_message_history(channel_id, message_ts)
        return nil unless response['ok'] && response['messages']&.any?

        response['messages'].find { |msg| msg['ts'] == message_ts }
      rescue ApiError => e
        @on_debug&.call("Could not fetch message #{message_ts} from #{channel_id}: #{e.message}")
        nil
      end

      private

      def fetch_message_history(channel_id, message_ts)
        # Use a narrow time window around the message timestamp
        oldest_ts = (message_ts.to_f - 1).to_s
        latest_ts = (message_ts.to_f + 1).to_s
        @api.history(channel: channel_id, limit: 10, oldest: oldest_ts, latest: latest_ts)
      end
    end
  end
end
