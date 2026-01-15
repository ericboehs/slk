# frozen_string_literal: true

module Slk
  module Support
    # Shared logic for resolving user and channel names from Slack data.
    # Include this module in commands that need to look up user/channel names.
    #
    # == Required Interface
    # Including classes must provide these methods:
    # - runner: Returns the Runner instance for API access
    # - cache_store: Returns the CacheStore for name lookups
    # - debug(message): Logs debug messages (can be a no-op)
    module UserResolver
      # Resolves a DM channel ID to the user's display name
      # @param workspace [Models::Workspace] The workspace to look up in
      # @param channel_id [String] The DM channel ID (starts with D)
      # @param conversations [Api::Conversations] API client for conversation info
      # @return [String] User name or channel ID if not found
      def resolve_dm_user_name(workspace, channel_id, conversations)
        user_id = get_dm_user_id(channel_id, conversations)
        return channel_id unless user_id

        lookup_user_name(workspace, user_id) || user_id
      rescue ApiError => e
        debug("DM info lookup failed for #{channel_id}: #{e.message}")
        channel_id
      end

      private

      def get_dm_user_id(channel_id, conversations)
        info = conversations.info(channel: channel_id)
        return nil unless info['ok'] && info['channel']

        info['channel']['user']
      end

      def lookup_user_name(workspace, user_id)
        cached = cache_store.get_user(workspace.name, user_id)
        return cached if cached

        fetch_and_cache_user_name(workspace, user_id)
      end

      def fetch_and_cache_user_name(workspace, user_id)
        users_api = runner.users_api(workspace.name)
        user_info = users_api.info(user_id)
        return nil unless user_info['ok'] && user_info['user']

        name = extract_name_from_user_info(user_info['user'])
        return nil unless name

        cache_store.set_user(workspace.name, user_id, name, persist: true)
        name
      rescue ApiError => e
        debug("User lookup failed for #{user_id}: #{e.message}")
        nil
      end

      def extract_name_from_user_info(user)
        profile = user['profile'] || {}
        name = profile['display_name']
        name = profile['real_name'] if name.to_s.empty?
        name = user['name'] if name.to_s.empty?
        name unless name.to_s.empty?
      end

      public

      # Resolves a channel ID to a formatted label (@username or #channel)
      # @param workspace [Models::Workspace] The workspace to look up in
      # @param channel_id [String] The channel ID
      # @return [String] Formatted label like "@username" or "#channel"
      def resolve_conversation_label(workspace, channel_id)
        return resolve_dm_label(workspace, channel_id) if channel_id.start_with?('D')

        resolve_channel_label(workspace, channel_id)
      end

      # Extracts the user name from a message hash
      # @param msg [Hash] The message data from API
      # @param workspace [Models::Workspace] The workspace context
      # @return [String] User name, user_id as fallback, or "unknown" if neither found
      def extract_user_from_message(msg, workspace)
        name_from_user_profile(msg) ||
          name_from_username(msg) ||
          name_from_cache(msg, workspace) ||
          msg['user'] || msg['bot_id'] || 'unknown'
      end

      private

      def resolve_dm_label(workspace, channel_id)
        conversations = runner.conversations_api(workspace.name)
        user_name = resolve_dm_user_name(workspace, channel_id, conversations)
        "@#{user_name}"
      end

      def resolve_channel_label(workspace, channel_id)
        cached_name = cache_store.get_channel_name(workspace.name, channel_id)
        return "##{cached_name}" if cached_name

        fetch_channel_label(workspace, channel_id)
      end

      def fetch_channel_label(workspace, channel_id)
        conversations = runner.conversations_api(workspace.name)
        response = conversations.info(channel: channel_id)
        return "##{channel_id}" unless response['ok'] && response['channel']

        name = response['channel']['name']
        return "##{channel_id}" unless name

        cache_store.set_channel(workspace.name, name, channel_id)
        "##{name}"
      rescue ApiError => e
        debug("Channel info lookup failed for #{channel_id}: #{e.message}")
        "##{channel_id}"
      end

      def name_from_user_profile(msg)
        return nil unless msg['user_profile']

        name = msg['user_profile']['display_name']
        name = msg['user_profile']['real_name'] if name.to_s.empty?
        name unless name.to_s.empty?
      end

      def name_from_username(msg)
        msg['username'] unless msg['username'].to_s.empty?
      end

      def name_from_cache(msg, workspace)
        user_id = msg['user'] || msg['bot_id']
        return nil unless user_id

        cache_store.get_user(workspace.name, user_id)
      end
    end
  end
end
