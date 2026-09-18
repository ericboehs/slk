# frozen_string_literal: true

module Slk
  module Services
    # Which custom profile field holds a start date, if any.
    #
    # Workspaces name and number these fields themselves, so the ID has to be
    # discovered from the team schema rather than hardcoded — and the schema
    # barely changes, so the answer is cached for a week.
    class StartDateField
      CACHE_KEY = 'start_date_field_v1'
      TTL = 604_800 # 7 days
      LABEL = /\Astart date\z/i

      def initialize(team_api:, workspace_name:, cache_store: nil, on_debug: nil)
        @team_api = team_api
        @workspace_name = workspace_name
        @cache = cache_store
        @on_debug = on_debug
      end

      # @return [String, nil] the Xf… field ID, or nil if the workspace has none
      def id
        return @id if defined?(@id)

        cached = MetaCache.read(@cache, @workspace_name, CACHE_KEY, ttl: TTL)
        @id = cached.is_a?(Hash) ? cached['id'] : discover
      end

      def missing_message
        'This workspace has no "Start Date" profile field, so tenure cannot be worked out. ' \
          'Run `slk debug schema` (an undocumented command) to see the fields it does have.'
      end

      private

      # A date-typed field wins over a text one with the same label: someone
      # typing "started summer 2019" into a text box is not a date.
      def discover
        id = usable_id(best_match(@team_api.profile_schema.dig('profile', 'fields')))
        @on_debug&.call("start date field: #{id || 'not found in team schema'}")
        remember(id)
        id
      end

      def usable_id(match)
        id = match && match['id']
        id.is_a?(String) && !id.empty? ? id : nil
      end

      # Losing this costs one extra team.profile.get next run, not minutes of
      # rate-limited lookups, so it is noted rather than warned about.
      def remember(id)
        failure = MetaCache.write(@cache, @workspace_name, CACHE_KEY, { 'id' => id })
        @on_debug&.call("start date field cache not written: #{failure.message}") if failure
      end

      # A workspace that answers with something other than a list of field
      # hashes has no start date field as far as we are concerned — better a
      # clear "this workspace cannot do tenure" than an unexpected error.
      def best_match(fields)
        labelled = Array(fields).grep(Hash).select { |f| LABEL.match?(f['label'].to_s.strip) }
        labelled.find { |f| f['type'] == 'date' } || labelled.first
      end
    end
  end
end
