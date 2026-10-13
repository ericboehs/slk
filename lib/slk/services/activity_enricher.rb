# frozen_string_literal: true

module Slk
  module Services
    # Enriches activity feed items with resolved user/channel names.
    # Group DMs show as "#name" when named, else "@other, members" (given a
    # GroupDmLabel), never as their mpdm-* slug, and are never cached by name.
    class ActivityEnricher
      def initialize(cache_store:, conversations_api:, group_dm_label: nil, on_debug: nil)
        @cache = cache_store
        @conversations_api = conversations_api
        @group_dm_label = group_dm_label
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

      # Resolve channel ID to a label (with API fallback). Legacy G ids are
      # group DMs or old private channels; they read "Group DM" if Slack
      # won't say which.
      def resolve_channel(workspace, channel_id, with_hash: true)
        return 'DM' if channel_id.start_with?('D')

        label = channel_label(workspace, channel_id)
        return channel_id.start_with?('G') ? 'Group DM' : channel_id unless label

        with_hash ? label : label.delete_prefix('#')
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

      def channel_label(workspace, channel_id)
        known = @group_dm_label&.known(workspace, channel_id)
        return known if known

        cached = @cache.get_channel_name(workspace.name, channel_id)
        return "##{cached}" if cached

        fetch_channel_label(workspace, channel_id)
      end

      def fetch_channel_label(workspace, channel_id)
        response = @conversations_api.info(channel: channel_id)
        channel = response['channel'] if response['ok']
        return nil unless channel
        return group_dm_label(workspace, channel_id, channel) if channel['is_mpim']
        return nil unless channel['name']

        @cache.set_channel(workspace.name, channel['name'], channel_id)
        "##{channel['name']}"
      rescue ApiError => e
        @on_debug&.call("Could not resolve channel #{channel_id}: #{e.message}")
        nil
      end

      def group_dm_label(workspace, channel_id, channel)
        return @group_dm_label.label_from(workspace, channel_id, channel) if @group_dm_label

        named = Support::GroupDmName.custom(channel)
        named ? "##{named}" : 'Group DM'
      end

      def debug_missing(item_type, missing_data)
        @on_debug&.call("Could not enrich #{item_type} item - missing #{missing_data} data")
      end
    end
  end
end
