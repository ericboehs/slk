# frozen_string_literal: true

module SlackCli
  module Formatters
    class MentionReplacer
      USER_MENTION_REGEX = /<@([UW][A-Z0-9]+)(?:\|([^>]+))?>/
      CHANNEL_MENTION_REGEX = /<#([A-Z0-9]+)(?:\|([^>]*))?>/
      SUBTEAM_MENTION_REGEX = /<!subteam\^([A-Z0-9]+)(?:\|@?([^>]+))?>/
      LINK_REGEX = /<(https?:\/\/[^|>]+)(?:\|([^>]+))?>/
      SPECIAL_MENTIONS = {
        "<!here>" => "@here",
        "<!channel>" => "@channel",
        "<!everyone>" => "@everyone"
      }.freeze

      def initialize(cache_store:, api_client: nil, on_debug: nil)
        @cache = cache_store
        @api = api_client
        @on_debug = on_debug
      end

      def replace(text, workspace)
        result = text.dup

        # Replace user mentions
        result.gsub!(USER_MENTION_REGEX) do
          user_id = ::Regexp.last_match(1)
          display_name = ::Regexp.last_match(2)

          if display_name && !display_name.empty?
            "@#{display_name}"
          else
            name = lookup_user_name(workspace, user_id)
            "@#{name || user_id}"
          end
        end

        # Replace channel mentions
        result.gsub!(CHANNEL_MENTION_REGEX) do
          channel_id = ::Regexp.last_match(1)
          channel_name = ::Regexp.last_match(2)

          if channel_name && !channel_name.empty?
            "##{channel_name}"
          else
            name = lookup_channel_name(workspace, channel_id)
            name ? "##{name}" : "##{channel_id}"
          end
        end

        # Replace subteam (user group) mentions
        result.gsub!(SUBTEAM_MENTION_REGEX) do
          subteam_id = ::Regexp.last_match(1)
          handle = ::Regexp.last_match(2)

          if handle && !handle.empty?
            "@#{handle}"
          else
            name = lookup_subteam_handle(workspace, subteam_id)
            "@#{name || subteam_id}"
          end
        end

        # Replace links
        result.gsub!(LINK_REGEX) do
          url = ::Regexp.last_match(1)
          label = ::Regexp.last_match(2)
          label || url
        end

        # Replace special mentions
        SPECIAL_MENTIONS.each do |pattern, replacement|
          result.gsub!(pattern, replacement)
        end

        result
      end

      private

      def lookup_user_name(workspace, user_id)
        # Try cache first
        cached = @cache.get_user(workspace.name, user_id)
        return cached if cached

        # Try API lookup
        return nil unless @api

        begin
          users_api = Api::Users.new(@api, workspace)
          response = users_api.info(user_id)
          if response["ok"] && response["user"]
            profile = response["user"]["profile"] || {}
            name = profile["display_name"]
            name = profile["real_name"] if name.to_s.empty?
            name = response["user"]["name"] if name.to_s.empty?
            # Cache for future lookups
            @cache.set_user(workspace.name, user_id, name, persist: true) if name && !name.empty?
            return name unless name.to_s.empty?
          end
        rescue ApiError => e
          @on_debug&.call("User lookup failed for #{user_id}: #{e.message}")
        end

        nil
      end

      def lookup_channel_name(workspace, channel_id)
        # Try cache first
        cached = @cache.get_channel_name(workspace.name, channel_id)
        return cached if cached

        # Try API lookup
        return nil unless @api

        begin
          conversations_api = Api::Conversations.new(@api, workspace)
          response = conversations_api.info(channel: channel_id)
          if response["ok"] && response["channel"]
            name = response["channel"]["name"]
            # Cache for future lookups
            @cache.set_channel(workspace.name, name, channel_id) if name
            return name
          end
        rescue ApiError => e
          @on_debug&.call("Channel lookup failed for #{channel_id}: #{e.message}")
        end

        nil
      end

      def lookup_subteam_handle(workspace, subteam_id)
        # Try cache first
        cached = @cache.get_subteam(workspace.name, subteam_id)
        return cached if cached

        # Try API lookup
        return nil unless @api

        begin
          usergroups_api = Api::Usergroups.new(@api, workspace)
          handle = usergroups_api.get_handle(subteam_id)
          # Cache for future lookups
          @cache.set_subteam(workspace.name, subteam_id, handle) if handle
          return handle
        rescue ApiError => e
          @on_debug&.call("Subteam lookup failed for #{subteam_id}: #{e.message}")
        end

        nil
      end
    end
  end
end
