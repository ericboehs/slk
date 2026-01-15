# frozen_string_literal: true

module SlackCli
  module Services
    # Adds timestamps to message reactions via activity API
    class ReactionEnricher
      def initialize(activity_api:)
        @activity_api = activity_api
      end

      # Enriches messages with reaction timestamps
      # Returns new array of messages with timestamps added to reactions
      def enrich_messages(messages, channel_id)
        return messages if messages.empty?

        # Fetch reaction activity
        activity_map = fetch_reaction_activity(channel_id, messages.map(&:ts))

        # Enhance messages with timestamps
        messages.map do |msg|
          enhanced_reactions = enhance_reactions(msg, activity_map)
          msg.with_reactions(enhanced_reactions)
        end
      end

      private

      def fetch_reaction_activity(_channel_id, message_timestamps)
        response = @activity_api.feed(limit: 50, types: 'message_reaction')
        return {} unless response['ok']

        build_activity_map(response['items'] || [], message_timestamps)
      rescue SlackCli::ApiError
        # If activity API fails, gracefully degrade - return empty map
        {}
      end

      def build_activity_map(items, message_timestamps)
        activity_map = {}
        items.each do |item|
          key, timestamp = extract_reaction_key(item, message_timestamps)
          activity_map[key] = timestamp if key
        end
        activity_map
      end

      def extract_reaction_key(item, message_timestamps)
        return nil unless item.dig('item', 'type') == 'message_reaction'

        msg_data = item.dig('item', 'message')
        reaction_data = item.dig('item', 'reaction')
        return nil unless msg_data && reaction_data

        msg_ts = msg_data['ts']
        return nil unless message_timestamps.include?(msg_ts)

        key = [msg_data['channel'], msg_ts, reaction_data['name'], reaction_data['user']].join(':')
        [key, item['feed_ts']]
      end

      def enhance_reactions(message, activity_map)
        return message.reactions if message.reactions.empty?

        message.reactions.map { |reaction| enhance_reaction(message, reaction, activity_map) }
      end

      def enhance_reaction(message, reaction, activity_map)
        timestamp_map = build_timestamp_map(message, reaction, activity_map)
        timestamp_map.empty? ? reaction : reaction.with_timestamps(timestamp_map)
      end

      def build_timestamp_map(message, reaction, activity_map)
        timestamp_map = {}
        reaction.users.each do |user_id|
          key = [message.channel_id, message.ts, reaction.name, user_id].join(':')
          timestamp_map[user_id] = activity_map[key] if activity_map[key]
        end
        timestamp_map
      end
    end
  end
end
