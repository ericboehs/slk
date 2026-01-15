# frozen_string_literal: true

module SlackCli
  module Services
    # Enriches activity feed items with resolved user/channel names
    class ActivityEnricher
      def initialize(cache_store:, conversations_api:, on_debug: nil)
        @cache = cache_store
        @conversations_api = conversations_api
        @on_debug = on_debug
      end

      # Enrich a list of activity items
      def enrich_all(items, workspace)
        items.map do |item|
          enriched = item.dup
          enrich_item(enriched, workspace)
          enriched
        end
      end

      # Enrich a single activity item based on its type
      def enrich_item(item, workspace)
        type = item.dig('item', 'type')
        dispatch_enrich(type, item, workspace)
      end

      def dispatch_enrich(type, item, workspace)
        case type
        when 'message_reaction' then enrich_reaction(item, workspace)
        when 'at_user', 'at_user_group', 'at_channel', 'at_everyone' then enrich_mention(item, workspace)
        when 'thread_v2' then enrich_thread(item, workspace)
        when 'bot_dm_bundle' then enrich_bot_dm(item, workspace)
        else @on_debug&.call("Unknown activity type: #{type.inspect}") if type
        end
      end

      # Resolve user ID to name (cache-only)
      def resolve_user(workspace, user_id)
        @cache.get_user(workspace.name, user_id) || user_id
      end

      # Resolve channel ID to name (with API fallback)
      def resolve_channel(workspace, channel_id, with_hash: true)
        return 'DM' if channel_id.start_with?('D')
        return 'Group DM' if channel_id.start_with?('G')

        name = fetch_channel_name(workspace, channel_id)
        return channel_id unless name

        with_hash ? "##{name}" : name
      end

      private

      def enrich_reaction(item, workspace)
        reaction_data = item.dig('item', 'reaction')
        message_data = item.dig('item', 'message')
        return debug_missing('reaction', 'reaction or message') unless reaction_data && message_data

        enrich_user(item, %w[item reaction], 'user', workspace)
        enrich_channel(item, %w[item message], 'channel', workspace)
      end

      def enrich_mention(item, workspace)
        message_data = item.dig('item', 'message')
        return debug_missing('mention', 'message') unless message_data

        user_id = message_data['author_user_id'] || message_data['user']
        item['item']['message']['user_name'] = resolve_user(workspace, user_id) if user_id
        enrich_channel(item, %w[item message], 'channel', workspace)
      end

      def enrich_thread(item, workspace)
        thread_entry = item.dig('item', 'bundle_info', 'payload', 'thread_entry')
        return debug_missing('thread', 'thread_entry') unless thread_entry

        enrich_channel(item, %w[item bundle_info payload thread_entry], 'channel_id', workspace)
      end

      def enrich_bot_dm(item, workspace)
        message_data = item.dig('item', 'bundle_info', 'payload', 'message')
        return debug_missing('bot DM', 'message') unless message_data

        enrich_channel(item, %w[item bundle_info payload message], 'channel', workspace)
      end

      def enrich_user(item, path, key, workspace)
        data = item.dig(*path)
        return unless data

        user_id = data[key]
        data['user_name'] = resolve_user(workspace, user_id) if user_id
      end

      def enrich_channel(item, path, key, workspace)
        data = item.dig(*path)
        return unless data

        channel_id = data[key]
        data['channel_name'] = resolve_channel(workspace, channel_id, with_hash: false) if channel_id
      end

      def fetch_channel_name(workspace, channel_id)
        cached = @cache.get_channel_name(workspace.name, channel_id)
        return cached if cached

        response = @conversations_api.info(channel: channel_id)
        return nil unless response['ok'] && response['channel']

        name = response['channel']['name']
        @cache.set_channel(workspace.name, name, channel_id)
        name
      rescue ApiError => e
        @on_debug&.call("Could not resolve channel #{channel_id}: #{e.message}")
        nil
      end

      def debug_missing(item_type, missing_data)
        @on_debug&.call("Could not enrich #{item_type} item - missing #{missing_data} data")
      end
    end
  end
end
