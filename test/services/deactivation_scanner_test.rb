# frozen_string_literal: true

require 'test_helper'

class DeactivationScannerTest < Minitest::Test
  # The scanner pages through the real Api::Users, so these tests cover the
  # cursor contract rather than a fake that stands in for it.
  def users_api(client)
    Slk::Api::Users.new(client, mock_workspace('test'))
  end

  def member(id, name:, **attrs)
    {
      'id' => id, 'name' => name, 'deleted' => attrs.fetch(:deleted, false),
      'updated' => attrs.fetch(:updated, 1_700_000_000), 'is_bot' => attrs.fetch(:bot, false),
      'is_restricted' => attrs.fetch(:restricted, false),
      'is_ultra_restricted' => attrs.fetch(:ultra_restricted, false),
      'profile' => { 'real_name' => name.capitalize, 'title' => 'Engineer' }
    }
  end

  def roster
    [
      [member('U1', name: 'ann', deleted: true, updated: 300),
       member('U2', name: 'bob')],
      [member('U3', name: 'cat', deleted: true, updated: 900),
       member('B1', name: 'deploybot', deleted: true, updated: 500, bot: true),
       member('U4', name: 'dan')]
    ]
  end

  def scanner(client, cache_store: nil, ttl: Slk::Services::DeactivationScanner::DEFAULT_TTL)
    Slk::Services::DeactivationScanner.new(
      users_api: users_api(client), workspace_name: 'test', cache_store: cache_store, ttl: ttl
    )
  end

  def cache_store
    @cache_store ||= Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
  end

  def test_scan_returns_only_deactivated_accounts_newest_first
    report = scanner(Slk::TestHelpers::PagedUsersClient.new(roster)).scan

    assert_equal %w[U3 B1 U1], report.records.map(&:user_id)
  end

  def test_scan_counts_humans_separately_from_bots
    report = scanner(Slk::TestHelpers::PagedUsersClient.new(roster)).scan

    assert_equal 5, report.member_count
    assert_equal 4, report.human_count
    assert_equal 2, report.active_count
    assert_equal 2, report.full_member_count
    assert_equal 0, report.multi_channel_guest_count
    assert_equal 0, report.single_channel_guest_count
    assert_equal 3, report.deactivated_count
    assert_equal 1, report.bots
  end

  def test_scan_breaks_down_active_accounts_by_guest_type
    pages = [[member('U1', name: 'full'),
              member('U2', name: 'multi', restricted: true),
              member('U3', name: 'single', restricted: true, ultra_restricted: true),
              member('U4', name: 'single2', ultra_restricted: true),
              member('U5', name: 'departed', deleted: true, restricted: true),
              member('B1', name: 'bot', bot: true, restricted: true)]]
    api = Slk::TestHelpers::PagedUsersClient.new(pages)
    scanner(api, cache_store: cache_store).scan
    report = scanner(api, cache_store: cache_store).scan

    assert_equal 1, api.calls.size, 'expected the breakdown to survive the cache round-trip'
    assert_equal 4, report.active_count
    assert_equal 1, report.full_member_count
    assert_equal 1, report.multi_channel_guest_count
    assert_equal 2, report.single_channel_guest_count
  end

  def test_records_without_timestamps_sort_last
    pages = [[member('U1', name: 'ann', deleted: true, updated: 0),
              member('U2', name: 'bob', deleted: true, updated: 10)]]
    report = scanner(Slk::TestHelpers::PagedUsersClient.new(pages)).scan

    assert_equal %w[U2 U1], report.records.map(&:user_id)
  end

  def test_second_scan_is_served_from_cache
    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    scanner(api, cache_store: cache_store).scan
    report = scanner(api, cache_store: cache_store).scan

    assert_equal 2, api.calls.size, 'expected the second scan to skip users.list'
    assert_equal 3, report.deactivated_count
  end

  def test_refresh_bypasses_the_cache
    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    scanner(api, cache_store: cache_store).scan
    scanner(api, cache_store: cache_store).scan(refresh: true)

    assert_equal 4, api.calls.size
  end

  # A negative TTL expires the entry the instant it is written, which is a way
  # to age the cache out inside a test without sleeping.
  def test_expired_cache_is_refetched
    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    scanner(api, cache_store: cache_store, ttl: -1).scan
    scanner(api, cache_store: cache_store, ttl: -1).scan

    assert_equal 4, api.calls.size
  end

  def test_scan_works_without_a_cache_store
    report = scanner(Slk::TestHelpers::PagedUsersClient.new(roster), cache_store: nil).scan

    assert_equal 3, report.deactivated_count
  end

  # Reading a truncated entry field by field would produce a confident "0
  # active accounts, 0 departures" rather than an admission that the cache is
  # unusable, so anything missing a required key is refetched.
  def test_malformed_cache_entry_is_refetched_not_coerced_to_zero
    cache_store.set_meta('test', Slk::Services::DeactivationScanner::CACHE_KEY, { 'records' => [] })
    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    report = scanner(api, cache_store: cache_store).scan

    assert_equal 2, api.calls.size
    assert_equal 2, report.active_count
    assert_equal 3, report.deactivated_count
  end

  def test_cache_entry_missing_guest_counts_is_refetched
    cache_store.set_meta('test', Slk::Services::DeactivationScanner::CACHE_KEY,
                         { 'fetched_at' => 1, 'member_count' => 1, 'human_count' => 1,
                           'active_count' => 1, 'records' => [] })
    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    report = scanner(api, cache_store: cache_store).scan

    assert_equal 2, api.calls.size
    assert_equal 2, report.full_member_count
  end

  def test_cache_entry_with_a_non_array_records_field_is_refetched
    cache_store.set_meta('test', Slk::Services::DeactivationScanner::CACHE_KEY,
                         { 'fetched_at' => 1, 'member_count' => 1, 'human_count' => 1,
                           'active_count' => 1, 'full_member_count' => 1,
                           'multi_channel_guest_count' => 0, 'single_channel_guest_count' => 0,
                           'records' => 'nope' })
    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    scanner(api, cache_store: cache_store).scan

    assert_equal 2, api.calls.size
  end

  def test_debug_callback_reports_an_unusable_cache
    cache_store.set_meta('test', Slk::Services::DeactivationScanner::CACHE_KEY, { 'records' => [] })
    messages = []
    Slk::Services::DeactivationScanner.new(
      users_api: users_api(Slk::TestHelpers::PagedUsersClient.new(roster)), workspace_name: 'test',
      cache_store: cache_store, on_debug: ->(msg) { messages << msg }
    ).scan

    assert(messages.any? { |m| m.include?('unusable') })
  end

  def test_progress_totals_are_reported_for_debug
    totals = []
    Slk::Services::DeactivationScanner.new(
      users_api: users_api(Slk::TestHelpers::PagedUsersClient.new(roster)), workspace_name: 'test',
      on_debug: ->(msg) { totals << msg }
    ).scan

    assert_equal ['users.list: 2 members fetched', 'users.list: 5 members fetched'], totals
  end

  # The roster scan is the cheap half of this command, but a read-only cache
  # dir used to abort it outright. A cache is an optimisation.
  def test_a_cache_that_cannot_be_written_does_not_stop_the_scan
    skip 'chmod does not prevent writes on Windows' if Gem.win_platform?

    api = Slk::TestHelpers::PagedUsersClient.new(roster)
    paths = Slk::TestHelpers::TempPaths.new
    store = Slk::Services::CacheStore.new(paths: paths)
    FileUtils.chmod(0o500, paths.dir)

    report = scanner(api, cache_store: store).scan

    refute_empty report.records
  ensure
    # skip raises, so paths may never have been assigned.
    FileUtils.chmod(0o700, paths.dir) if paths
  end
end
