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
        when :user then lookup_user_name(workspace, id)
        when :channel then lookup_channel_name(workspace, id)
        when :subteam then lookup_subteam_handle(workspace, id)
        end
      end

      def lookup_user_name(workspace, user_id)
        cached = @cache.get_user(workspace.name, user_id)
        return cached if cached

        fetch_user_name_from_api(workspace, user_id)
      end

      def fetch_user_name_from_api(workspace, user_id)
        return nil unless @api

        response = Api::Users.new(@api, workspace).info(user_id)
        return nil unless response['ok'] && response['user']

        name = extract_user_display_name(response['user'])
        cache_user_name(workspace, user_id, name)
        name
      rescue ApiError => e
        @on_debug&.call("User lookup failed for #{user_id}: #{e.message}")
        nil
      end

      def cache_user_name(workspace, user_id, name)
        @cache.set_user(workspace.name, user_id, name, persist: true) unless name.to_s.empty?
      end

      def extract_user_display_name(user)
        profile = user['profile'] || {}
        profile['display_name'].then { |n| n.to_s.empty? ? nil : n } ||
          profile['real_name'].then { |n| n.to_s.empty? ? nil : n } ||
          user['name'].then { |n| n.to_s.empty? ? nil : n }
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
