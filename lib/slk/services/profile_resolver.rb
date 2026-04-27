# frozen_string_literal: true

module Slk
  module Services
    # Orchestrates the API calls needed to assemble a Models::Profile.
    # Memoizes within the instance — one resolver per command run.
    class ProfileResolver
      SCHEMA_TTL = 86_400 # 24h
      PROFILE_TTL = 3_600 # 1h
      EMPTY_SCHEMA = { 'ok' => false, 'profile' => { 'fields' => [], 'sections' => [] } }.freeze

      attr_accessor :refresh

      def initialize(users_api:, team_api:, cache_store: nil, workspace_name: nil, on_debug: nil)
        @users_api = users_api
        @team_api = team_api
        @cache_store = cache_store
        @workspace_name = workspace_name
        @on_debug = on_debug
        @refresh = false
        @profile_cache = {}
        @home_team_names = {}
      end

      # Resolve a user ID to a Profile. Memoized per resolver instance.
      def resolve(user_id)
        return @profile_cache[user_id] if @profile_cache.key?(user_id)

        @profile_cache[user_id] = build_profile(user_id)
      end

      # Resolve a profile and one level of type:user custom fields, populating
      # `resolved_users` so the formatter can render the People section.
      def resolve_with_people(user_id)
        profile = resolve(user_id)
        return profile if profile.external?

        profile.people_fields.flat_map(&:user_ids).uniq.each do |ref_id|
          profile.resolved_users[ref_id] ||= resolve(ref_id)
        end
        profile
      end

      # Walks Supervisor (or first non-inverse type:user field) upward.
      # Returns Array<Profile> from immediate supervisor to top, capped by depth.
      def resolve_chain_up(user_id, depth: 5)
        chain = []
        seen = Set.new([user_id])
        current = resolve(user_id)
        depth.times { current = step_up(current, seen, chain) or break }
        chain
      end

      private

      def step_up(current, seen, chain)
        parent_id = current.supervisor_ids.first
        return nil unless parent_id && !seen.include?(parent_id)

        parent = resolve(parent_id)
        chain << parent
        seen << parent.user_id
        parent
      end

      def build_profile(user_id)
        profile = ProfileBuilder.build(
          profile_response: fetch_profile_response(user_id),
          info_response: cache_or_fetch("ui_#{user_id}", ttl: PROFILE_TTL) { @users_api.info(user_id) },
          schema_response: schema,
          workspace_team_id: workspace_team_id
        )
        attach_extras(profile, user_id)
      rescue ApiError => e
        @on_debug&.call("Profile resolve failed for #{user_id}: #{e.message}")
        raise
      end

      # Only swallow `user_not_found` (Slack Connect); other errors propagate.
      def fetch_profile_response(user_id)
        key = "up_#{user_id}"
        cached = MetaCache.read(@cache_store, @workspace_name, key, ttl: PROFILE_TTL) unless @refresh
        return cached if cached

        response = @users_api.profile_for(user_id)
        MetaCache.write(@cache_store, @workspace_name, key, response)
        response
      rescue ApiError => e
        raise unless e.code == :user_not_found

        @on_debug&.call("#{key}: #{e.message} (falling back to users.info)")
        nil
      end

      def attach_extras(profile, user_id)
        profile = attach_home_team_name(profile)
        presence = fetch_presence(user_id)
        presence ? Models::Profile.new(**profile.to_h, presence: presence) : profile
      end

      def fetch_presence(user_id)
        @users_api.get_presence_for(user_id)&.dig('presence')
      rescue ApiError => e
        @on_debug&.call("get_presence_for(#{user_id}) failed: #{e.message}")
        nil
      end

      def schema
        @schema ||= cache_or_fetch('team_profile_schema', ttl: SCHEMA_TTL,
                                                          empty: EMPTY_SCHEMA) { @team_api.profile_schema }
      end

      def workspace_team_id
        @workspace_team_id ||= cache_or_fetch('workspace_team_id') { @team_api.info.dig('team', 'id') }
      end

      def cache_or_fetch(key, ttl: nil, empty: nil, &)
        MetaCache.fetch(@cache_store, @workspace_name, key, ttl: ttl, refresh: @refresh, &)
      rescue ApiError => e
        @on_debug&.call("#{key} fetch failed: #{e.message}")
        empty
      end

      def attach_home_team_name(profile)
        return profile unless profile.external? && profile.team_id && (name = home_team_name(profile.team_id))

        Models::Profile.new(**profile.to_h, home_team_name: name)
      end

      def home_team_name(team_id)
        @home_team_names[team_id] ||= @team_api.info(team_id).dig('team', 'name')
      rescue ApiError => e
        @on_debug&.call("team.info(#{team_id}) failed: #{e.message}")
        @home_team_names[team_id] = nil
      end
    end
  end
end
