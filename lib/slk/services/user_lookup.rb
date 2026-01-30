# frozen_string_literal: true

module Slk
  module Services
    # Consolidated service for user name resolution
    # Provides ID → name and name → ID lookups with caching
    class UserLookup
      def initialize(cache_store:, workspace:, api_client: nil, on_debug: nil)
        @cache = cache_store
        @api = api_client
        @workspace = workspace
        @on_debug = on_debug
      end

      # Resolve user ID to display name (most common use case)
      # @param user_id [String] Slack user ID (e.g., "U123ABC")
      # @return [String, nil] Display name or nil if not found
      def resolve_name(user_id)
        return nil if user_id.to_s.empty?

        cached = @cache.get_user(@workspace.name, user_id)
        return cached if cached

        fetch_and_cache_name(user_id)
      end

      # Resolve user ID to display name, handling bots
      # @param user_id [String] Slack user or bot ID
      # @return [String, nil] Display name or nil if not found
      def resolve_name_or_bot(user_id)
        return nil if user_id.to_s.empty?

        cached = @cache.get_user(@workspace.name, user_id)
        return cached if cached

        if user_id.start_with?('B')
          fetch_and_cache_bot_name(user_id)
        else
          fetch_and_cache_name(user_id)
        end
      end

      # Find user ID by display name (reverse lookup)
      # @param name [String] Display name to search for
      # @return [String, nil] User ID or nil if not found
      def find_id_by_name(name)
        return nil if name.to_s.empty?

        cached = @cache.get_user_id_by_name(@workspace.name, name)
        return cached if cached

        fetch_id_by_name(name)
      end

      private

      def fetch_and_cache_name(user_id)
        return nil unless @api

        user = fetch_user(user_id)
        return nil unless user

        @cache.set_user(@workspace.name, user_id, user.best_name, persist: true)
        user.best_name
      rescue ApiError => e
        @on_debug&.call("User lookup failed for #{user_id}: #{e.message}")
        nil
      end

      def fetch_and_cache_bot_name(bot_id)
        return nil unless @api

        bots_api = Api::Bots.new(@api, @workspace, on_debug: @on_debug)
        name = bots_api.get_name(bot_id)
        @cache.set_user(@workspace.name, bot_id, name, persist: true) if name
        name
      rescue ApiError => e
        @on_debug&.call("Bot lookup failed for #{bot_id}: #{e.message}")
        nil
      end

      def fetch_user(user_id)
        users_api = Api::Users.new(@api, @workspace, on_debug: @on_debug)
        response = users_api.info(user_id)
        return nil unless response['ok'] && response['user']

        Models::User.from_api(response['user'])
      end

      def fetch_id_by_name(name)
        return nil unless @api

        users_api = Api::Users.new(@api, @workspace, on_debug: @on_debug)
        users = users_api.list['members'] || []
        user = find_user_by_name(users, name)
        cache_user_from_api(user) if user
        user&.dig('id')
      rescue ApiError => e
        @on_debug&.call("User list lookup failed: #{e.message}")
        nil
      end

      def find_user_by_name(users, name)
        users.find do |u|
          u['name'] == name ||
            u.dig('profile', 'display_name') == name ||
            u.dig('profile', 'real_name') == name
        end
      end

      def cache_user_from_api(user_data)
        user = Models::User.from_api(user_data)
        @cache.set_user(@workspace.name, user.id, user.best_name, persist: true)
      end
    end
  end
end
