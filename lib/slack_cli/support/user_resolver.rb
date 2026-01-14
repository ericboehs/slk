# frozen_string_literal: true

module SlackCli
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
        info = conversations.info(channel: channel_id)
        return channel_id unless info["ok"] && info["channel"]

        user_id = info["channel"]["user"]
        return channel_id unless user_id

        # Try cache first
        cached = cache_store.get_user(workspace.name, user_id)
        return cached if cached

        # Try users API lookup
        begin
          users_api = runner.users_api(workspace.name)
          user_info = users_api.info(user_id)
          if user_info["ok"] && user_info["user"]
            profile = user_info["user"]["profile"] || {}
            name = profile["display_name"]
            name = profile["real_name"] if name.to_s.empty?
            name = user_info["user"]["name"] if name.to_s.empty?
            if name && !name.empty?
              cache_store.set_user(workspace.name, user_id, name, persist: true)
              return name
            end
          end
        rescue ApiError => e
          debug("User lookup failed for #{user_id}: #{e.message}")
        end

        user_id
      rescue ApiError => e
        debug("DM info lookup failed for #{channel_id}: #{e.message}")
        channel_id
      end

      # Resolves a channel ID to a formatted label (@username or #channel)
      # @param workspace [Models::Workspace] The workspace to look up in
      # @param channel_id [String] The channel ID
      # @return [String] Formatted label like "@username" or "#channel"
      def resolve_conversation_label(workspace, channel_id)
        # DM channels start with D
        if channel_id.start_with?("D")
          conversations = runner.conversations_api(workspace.name)
          user_name = resolve_dm_user_name(workspace, channel_id, conversations)
          return "@#{user_name}"
        end

        # Try cache first
        cached_name = cache_store.get_channel_name(workspace.name, channel_id)
        return "##{cached_name}" if cached_name

        # Try API lookup
        begin
          conversations = runner.conversations_api(workspace.name)
          response = conversations.info(channel: channel_id)
          if response["ok"] && response["channel"]
            name = response["channel"]["name"]
            if name
              cache_store.set_channel(workspace.name, name, channel_id)
              return "##{name}"
            end
          end
        rescue ApiError => e
          debug("Channel info lookup failed for #{channel_id}: #{e.message}")
        end

        "##{channel_id}"
      end

      # Extracts the user name from a message hash
      # @param msg [Hash] The message data from API
      # @param workspace [Models::Workspace] The workspace context
      # @return [String] User name, user_id as fallback, or "unknown" if neither found
      def extract_user_from_message(msg, workspace)
        # Try user_profile embedded in message
        if msg["user_profile"]
          name = msg["user_profile"]["display_name"]
          name = msg["user_profile"]["real_name"] if name.to_s.empty?
          return name unless name.to_s.empty?
        end

        # Try username field
        return msg["username"] unless msg["username"].to_s.empty?

        # Try cache
        user_id = msg["user"] || msg["bot_id"]
        if user_id
          cached = cache_store.get_user(workspace.name, user_id)
          return cached if cached
        end

        user_id || "unknown"
      end
    end
  end
end
