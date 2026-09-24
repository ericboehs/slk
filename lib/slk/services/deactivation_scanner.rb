# frozen_string_literal: true

module Slk
  module Services
    # Slack has no "who left" endpoint. What it does have is users.list, which
    # returns deactivated accounts with `deleted: true` and an `updated` epoch
    # for the last change to the account — and for a deactivated account that
    # change is nearly always the deactivation itself.
    #
    # The full roster is one API call per 1000 members, so the derived result
    # (deactivated members plus headcounts, not the whole roster) is cached in
    # the workspace meta cache with a TTL.
    class DeactivationScanner
      CACHE_KEY = 'deactivations_v2'
      DEFAULT_TTL = 21_600 # 6 hours
      REQUIRED_KEYS = %w[
        fetched_at member_count human_count active_count full_member_count
        multi_channel_guest_count single_channel_guest_count records
      ].freeze

      Report = Data.define(
        :records, :member_count, :human_count, :active_count, :full_member_count,
        :multi_channel_guest_count, :single_channel_guest_count, :fetched_at
      ) do
        def deactivated_count = records.size

        def bots = records.count(&:bot)
      end

      def initialize(users_api:, workspace_name:, cache_store: nil, ttl: DEFAULT_TTL, on_debug: nil)
        @users_api = users_api
        @workspace_name = workspace_name
        @cache = cache_store
        @ttl = ttl
        @on_debug = on_debug
      end

      # @return [Report] every deactivated account, newest deactivation first
      def scan(refresh: false)
        build_report(cached(refresh: refresh) || store(collect))
      end

      private

      def cached(refresh:)
        return nil if refresh

        data = MetaCache.read(@cache, @workspace_name, CACHE_KEY, ttl: @ttl)
        return data if usable?(data)

        @on_debug&.call('deactivations cache is unusable; re-fetching the roster') if data
        nil
      end

      # A truncated or older-shaped entry would otherwise be read field by
      # field into a report of zero active members and zero departures — a
      # confident, wrong answer. Missing anything required means refetch.
      def usable?(data)
        data.is_a?(Hash) && data['records'].is_a?(Array) && REQUIRED_KEYS.all? { |key| data[key] }
      end

      def store(data)
        MetaCache.write(@cache, @workspace_name, CACHE_KEY, data)
        data
      end

      def collect
        members = fetch_members
        deleted = members.select { |m| m['deleted'] }

        counts(members).merge(
          'fetched_at' => Time.now.to_i,
          'records' => deleted.map { |m| Models::Deactivation.from_api(m).to_cache }
        )
      end

      def counts(members)
        humans = members.reject { |m| Models::Deactivation.bot?(m) }
        active = humans.reject { |m| m['deleted'] }

        {
          'member_count' => members.size,
          'human_count' => humans.size,
          'active_count' => active.size
        }.merge(guest_counts(active))
      end

      def guest_counts(active)
        groups = active.group_by { |member| guest_type(member) }
        {
          'full_member_count' => groups.fetch(:full, []).size,
          'multi_channel_guest_count' => groups.fetch(:multi, []).size,
          'single_channel_guest_count' => groups.fetch(:single, []).size
        }
      end

      def guest_type(member)
        return :single if member['is_ultra_restricted']
        return :multi if member['is_restricted']

        :full
      end

      def fetch_members
        @users_api.list_all do |total|
          @on_debug&.call("users.list: #{total} members fetched")
        end
      end

      # Keep the cache fields explicit: a missing headcount must not become a
      # plausible-looking zero without usable? first checking the cache shape.
      # rubocop:disable Metrics/AbcSize
      def build_report(data)
        Report.new(
          records: sorted_records(data['records'] || []),
          member_count: data['member_count'].to_i,
          human_count: data['human_count'].to_i,
          active_count: data['active_count'].to_i,
          full_member_count: data['full_member_count'].to_i,
          multi_channel_guest_count: data['multi_channel_guest_count'].to_i,
          single_channel_guest_count: data['single_channel_guest_count'].to_i,
          fetched_at: data['fetched_at']&.to_i
        )
      end

      # rubocop:enable Metrics/AbcSize

      # Newest first; accounts with no usable timestamp sort to the bottom
      # rather than pretending to be from 1970.
      def sorted_records(raw)
        raw.map { |hash| Models::Deactivation.from_cache(hash) }
           .sort_by { |record| -(record.deactivated_at || 0) }
      end
    end
  end
end
