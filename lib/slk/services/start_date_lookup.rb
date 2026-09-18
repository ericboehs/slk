# frozen_string_literal: true

module Slk
  module Services
    # Start dates live in a workspace custom profile field, which `users.list`
    # does not return — they cost one `users.profile.get` per person, and Slack
    # rate-limits that endpoint hard enough that a screenful takes minutes
    # rather than seconds.
    #
    # So every answer is cached, and cached the moment it arrives rather than
    # at the end: interrupting a long lookup keeps the work already paid for.
    # Accounts with no start date on file are cached too, otherwise every run
    # would pay again to learn the same nothing.
    class StartDateLookup
      CACHE_KEY = 'start_dates_v1'
      TTL = 2_592_000 # 30 days — a departed account's start date is settled

      class MissingFieldError < Slk::Error; end

      def initialize(users_api:, field:, workspace_name:, cache_store: nil, on_progress: nil)
        @users_api = users_api
        @field = field
        @workspace_name = workspace_name
        @cache = cache_store
        @on_progress = on_progress
      end

      # @return [Hash{String => String, nil}] user ID => ISO date, or nil for
      #   an account with no start date recorded
      def fetch(user_ids)
        return {} if user_ids.empty?
        raise MissingFieldError, @field.missing_message unless @field.id

        known = cached
        user_ids.each_with_index { |id, index| resolve(known, id, index, user_ids.size) }
        known.slice(*user_ids)
      end

      # How many of these would cost an API call, so a caller can warn about
      # the wait before making someone sit through it.
      def uncached_count(user_ids)
        known = cached
        user_ids.count { |id| !known.key?(id) }
      end

      private

      def resolve(known, user_id, index, total)
        return if known.key?(user_id)

        @on_progress&.call(index + 1, total)
        known[user_id] = start_date_for(user_id)
        MetaCache.write(@cache, @workspace_name, CACHE_KEY, known)
      end

      def start_date_for(user_id)
        fields = @users_api.profile_for(user_id).dig('profile', 'fields')
        value = fields.is_a?(Hash) ? fields.dig(@field.id, 'value') : nil
        value.to_s.empty? ? nil : value
      end

      def cached
        @cached ||= begin
          data = MetaCache.read(@cache, @workspace_name, CACHE_KEY, ttl: TTL)
          data.is_a?(Hash) ? data : {}
        end
      end
    end
  end
end
