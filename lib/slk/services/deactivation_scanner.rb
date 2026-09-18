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
      CACHE_KEY = 'deactivations_v1'
      DEFAULT_TTL = 21_600 # 6 hours

      Report = Data.define(:records, :member_count, :human_count, :active_count, :fetched_at) do
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
        data = MetaCache.fetch(@cache, @workspace_name, CACHE_KEY, ttl: @ttl, refresh: refresh) { collect }
        build_report(data)
      end

      private

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

        {
          'member_count' => members.size,
          'human_count' => humans.size,
          'active_count' => humans.count { |m| !m['deleted'] }
        }
      end

      def fetch_members
        @users_api.list_all do |total|
          @on_debug&.call("users.list: #{total} members fetched")
        end
      end

      def build_report(data)
        Report.new(
          records: sorted_records(data['records'] || []),
          member_count: data['member_count'].to_i,
          human_count: data['human_count'].to_i,
          active_count: data['active_count'].to_i,
          fetched_at: data['fetched_at']&.to_i
        )
      end

      # Newest first; accounts with no usable timestamp sort to the bottom
      # rather than pretending to be from 1970.
      def sorted_records(raw)
        raw.map { |hash| Models::Deactivation.from_cache(hash) }
           .sort_by { |record| -(record.deactivated_at || 0) }
      end
    end
  end
end
