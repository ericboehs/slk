# frozen_string_literal: true

module Slk
  module Formatters
    # Replaces Slack mention syntax with readable @names and #channels
    # rubocop:disable Metrics/ClassLength
    class MentionReplacer
      USER_MENTION_REGEX = /<@([UW][A-Z0-9]+)(?:\|([^>]+))?>/
      CHANNEL_MENTION_REGEX = /<#([A-Z0-9]+)(?:\|([^>]*))?>/
      SUBTEAM_MENTION_REGEX = /<!subteam\^([A-Z0-9]+)(?:\|@?([^>]+))?>/
      LINK_REGEX = %r{<(https?://[^|>]+)(?:\|([^>]+))?>}
      SPECIAL_MENTIONS = {
        '<!here>' => '@here',
        '<!channel>' => '@channel',
        '<!everyone>' => '@everyone'
      }.freeze

      def initialize(cache_store:, api_client: nil, on_debug: nil)
        @cache = cache_store
        @api = api_client
        @on_debug = on_debug
      end

      def replace(text, workspace)
        result = text.dup
        result = replace_user_mentions(result, workspace)
        result = replace_channel_mentions(result, workspace)
        result = replace_subteam_mentions(result, workspace)
        result = replace_links(result)
        replace_special_mentions(result)
      end

      # Public API for looking up user names (used by MessageFormatter)
      def lookup_user_name(workspace, user_id)
        user_lookup_for(workspace).resolve_name(user_id)
      end

      private

      def replace_user_mentions(text, workspace)
        text.gsub(USER_MENTION_REGEX) do
          user_id = ::Regexp.last_match(1)
          display_name = ::Regexp.last_match(2)
          name = display_name_or_lookup(display_name, workspace, user_id, :user)
          "@#{name}"
        end
      end

      def replace_channel_mentions(text, workspace)
        text.gsub(CHANNEL_MENTION_REGEX) do
          channel_id = ::Regexp.last_match(1)
          channel_name = ::Regexp.last_match(2)
          name = display_name_or_lookup(channel_name, workspace, channel_id, :channel)
          "##{name}"
        end
      end

      def replace_subteam_mentions(text, workspace)
        text.gsub(SUBTEAM_MENTION_REGEX) do
          subteam_id = ::Regexp.last_match(1)
          handle = ::Regexp.last_match(2)
          name = display_name_or_lookup(handle, workspace, subteam_id, :subteam)
          "@#{name}"
        end
      end

      def replace_links(text)
        text.gsub(LINK_REGEX) { ::Regexp.last_match(2) || ::Regexp.last_match(1) }
      end

      def replace_special_mentions(text)
        SPECIAL_MENTIONS.each { |pattern, replacement| text.gsub!(pattern, replacement) }
        text
      end

      def display_name_or_lookup(display_name, workspace, id, type)
        return display_name unless display_name.to_s.empty?

        lookup_by_type(workspace, id, type) || id
      end

      def lookup_by_type(workspace, id, type)
        case type
        when :user then user_lookup_for(workspace).resolve_name(id)
        when :channel then lookup_channel_name(workspace, id)
        when :subteam then lookup_subteam_handle(workspace, id)
        end
      end

      def user_lookup_for(workspace)
        Services::UserLookup.new(
          cache_store: @cache,
          workspace: workspace,
          api_client: @api,
          on_debug: @on_debug
        )
      end

      def lookup_channel_name(workspace, channel_id)
        cached = @cache.get_channel_name(workspace.name, channel_id)
        return cached if cached

        fetch_channel_name_from_api(workspace, channel_id)
      end

      def fetch_channel_name_from_api(workspace, channel_id)
        return nil unless @api

        response = Api::Conversations.new(@api, workspace).info(channel: channel_id)
        return nil unless response['ok'] && response['channel']

        name = response['channel']['name']
        @cache.set_channel(workspace.name, name, channel_id) if name
        name
      rescue ApiError => e
        @on_debug&.call("Channel lookup failed for #{channel_id}: #{e.message}")
        nil
      end

      def lookup_subteam_handle(workspace, subteam_id)
        cached = @cache.get_subteam(workspace.name, subteam_id)
        return cached if cached

        fetch_subteam_handle_from_api(workspace, subteam_id)
      end

      def fetch_subteam_handle_from_api(workspace, subteam_id)
        return nil unless @api

        handle = Api::Usergroups.new(@api, workspace).get_handle(subteam_id)
        @cache.set_subteam(workspace.name, subteam_id, handle) if handle
        handle
      rescue ApiError => e
        @on_debug&.call("Subteam lookup failed for #{subteam_id}: #{e.message}")
        nil
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
