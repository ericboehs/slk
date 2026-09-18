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
    #
    # The cache holds for 30 days. A departed account's start date rarely
    # changes, but an admin correcting a typo in one is exactly the case the
    # expiry exists for; `slk cache clear` forces the issue sooner.
    class StartDateLookup
      CACHE_KEY = 'start_dates_v1'
      TTL = 2_592_000 # 30 days

      class MissingFieldError < Slk::Error; end

      # Set when the cache could not be written. The lookup carries on — the
      # cache is an optimisation, and the answers are worth more than it.
      attr_reader :cache_error

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
        # Checked even for an empty list: "this workspace cannot do tenure" is
        # the same fact whether or not anyone matched the filter, and finding
        # out only when someone matches makes it look intermittent.
        raise MissingFieldError, @field.missing_message if @field.id.to_s.empty?
        return {} if user_ids.empty?

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
        remember(known)
      end

      # A full or read-only disk must not throw away a lookup that cost
      # minutes of rate-limited calls. MetaCache.write hands back the failure
      # instead of raising; the caller reports it once at the end.
      def remember(known)
        failure = MetaCache.write(@cache, @workspace_name, CACHE_KEY, known)
        # First failure only: the same unwritable disk will fail every row.
        @cache_error = failure.message if failure && @cache_error.nil?
      end

      # Which account failed matters when the answer arrives twenty rows into
      # a run that has already taken three minutes.
      def start_date_for(user_id)
        fields = @users_api.profile_for(user_id).dig('profile', 'fields')
        value = fields.is_a?(Hash) ? fields.dig(@field.id, 'value') : nil
        value.to_s.empty? ? nil : value
      rescue ApiError => e
        # Only the plain kind: re-wrapping a RateLimitError would drop its
        # retry_after and the class the retry logic looks for.
        raise unless e.instance_of?(ApiError)

        raise ApiError.new("#{e.message} (looking up #{user_id})", code: e.code)
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
