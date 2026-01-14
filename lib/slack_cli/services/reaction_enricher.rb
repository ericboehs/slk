# frozen_string_literal: true

module SlackCli
  module Services
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
        # Fetch first page of recent reactions (max 50 per API limit)
        # Note: This may not cover all historical reactions, but that's acceptable
        # for performance reasons. Older reactions simply won't have timestamps.
        response = @activity_api.feed(limit: 50, types: 'message_reaction')
        return {} unless response['ok']

        # Build map: "channel_id:message_ts:emoji:user" => timestamp
        activity_map = {}
        items = response['items'] || []

        items.each do |item|
          next unless item.dig('item', 'type') == 'message_reaction'

          msg_data = item.dig('item', 'message')
          reaction_data = item.dig('item', 'reaction')
          next unless msg_data && reaction_data

          # Only include reactions for messages we care about
          msg_ts = msg_data['ts']
          next unless message_timestamps.include?(msg_ts)

          key = [
            msg_data['channel'],
            msg_ts,
            reaction_data['name'],
            reaction_data['user']
          ].join(':')

          activity_map[key] = item['feed_ts']
        end

        activity_map
      rescue SlackCli::ApiError
        # If activity API fails, gracefully degrade - return empty map
        # Messages will still be displayed, just without reaction timestamps
        {}
      end

      def enhance_reactions(message, activity_map)
        return message.reactions if message.reactions.empty?

        message.reactions.map do |reaction|
          timestamp_map = {}

          reaction.users.each do |user_id|
            key = [message.channel_id, message.ts, reaction.name, user_id].join(':')
            timestamp_map[user_id] = activity_map[key] if activity_map[key]
          end

          # Only create a new reaction with timestamps if we found any
          if timestamp_map.empty?
            reaction
          else
            reaction.with_timestamps(timestamp_map)
          end
        end
      end
    end
  end
end
