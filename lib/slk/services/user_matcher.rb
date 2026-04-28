# frozen_string_literal: true

module Slk
  module Services
    # Finds all users whose name/display/real/first+last matches a query
    # (case-insensitive). Combines users.list with previously-resolved profiles
    # cached locally — Slack Connect external users don't appear in users.list
    # but do show up in the meta cache once users.info has been fetched.
    class UserMatcher
      def initialize(api_client:, workspace:, cache_store:, on_debug: nil)
        @api = api_client
        @workspace = workspace
        @cache = cache_store
        @on_debug = on_debug
      end

      # Returns users.list-shaped hashes (deduped by id). Raises ApiError on
      # network/auth failures so callers don't conflate them with "no matches".
      def find_all(name)
        return [] if name.to_s.empty? || @api.nil?

        target = name.downcase
        candidates = list_members + cached_profile_users
        unique_by_id(candidates.select { |u| matches?(u, target) })
      end

      def matches?(user, target_lower)
        name_candidates(user).any? { |c| c.downcase == target_lower }
      end

      def name_candidates(user)
        profile = user['profile'] || {}
        full = [profile['first_name'], profile['last_name']].compact.join(' ').strip
        [user['name'], profile['display_name'], profile['real_name'], full]
          .map(&:to_s).reject(&:empty?)
      end

      private

      def list_members
        Api::Users.new(@api, @workspace, on_debug: @on_debug).list['members'] || []
      end

      # Reshape cached `ui_<uid>` meta entries (raw users.info responses) into
      # users.list-shaped hashes so the matcher can compare them uniformly.
      def cached_profile_users
        return [] unless @cache.respond_to?(:each_meta)

        @cache.each_meta(@workspace.name).filter_map do |key, value|
          next unless key.start_with?('ui_')

          user = value.is_a?(Hash) ? value.dig('value', 'user') : nil
          user if user.is_a?(Hash) && user['id']
        end
      end

      def unique_by_id(users)
        seen = {}
        users.each { |u| seen[u['id']] ||= u }
        seen.values
      end
    end
  end
end
