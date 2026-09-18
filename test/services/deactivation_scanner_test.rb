# frozen_string_literal: true

require 'test_helper'

class DeactivationScannerTest < Minitest::Test
  # users.list is paginated, so the fake returns a scripted sequence of pages
  # rather than one canned response.
  class PagedUsersApi
    attr_reader :call_count

    def initialize(pages)
      @pages = pages
      @call_count = 0
    end

    def list_all(limit: 1000) # rubocop:disable Lint/UnusedMethodArgument
      members = []
      @pages.each do |page|
        @call_count += 1
        members.concat(page)
        yield(members.size) if block_given?
      end
      members
    end
  end

  def member(id, name:, deleted: false, updated: 1_700_000_000, bot: false)
    {
      'id' => id, 'name' => name, 'deleted' => deleted, 'updated' => updated, 'is_bot' => bot,
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

  def scanner(api, cache_store: nil, ttl: Slk::Services::DeactivationScanner::DEFAULT_TTL)
    Slk::Services::DeactivationScanner.new(
      users_api: api, workspace_name: 'test', cache_store: cache_store, ttl: ttl
    )
  end

  def cache_store
    @cache_store ||= Slk::Services::CacheStore.new(paths: TempPaths.new)
  end

  class TempPaths
    def initialize = @dir = Dir.mktmpdir('slk-deactivations-test')
    def cache_file(name) = File.join(@dir, name)
    def ensure_cache_dir = FileUtils.mkdir_p(@dir)
  end

  def test_scan_returns_only_deactivated_accounts_newest_first
    report = scanner(PagedUsersApi.new(roster)).scan

    assert_equal %w[U3 B1 U1], report.records.map(&:user_id)
  end

  def test_scan_counts_humans_separately_from_bots
    report = scanner(PagedUsersApi.new(roster)).scan

    assert_equal 5, report.member_count
    assert_equal 4, report.human_count
    assert_equal 2, report.active_count
    assert_equal 3, report.deactivated_count
    assert_equal 1, report.bots
  end

  def test_records_without_timestamps_sort_last
    pages = [[member('U1', name: 'ann', deleted: true, updated: 0),
              member('U2', name: 'bob', deleted: true, updated: 10)]]
    report = scanner(PagedUsersApi.new(pages)).scan

    assert_equal %w[U2 U1], report.records.map(&:user_id)
  end

  def test_second_scan_is_served_from_cache
    api = PagedUsersApi.new(roster)
    scanner(api, cache_store: cache_store).scan
    report = scanner(api, cache_store: cache_store).scan

    assert_equal 2, api.call_count, 'expected the second scan to skip users.list'
    assert_equal 3, report.deactivated_count
  end

  def test_refresh_bypasses_the_cache
    api = PagedUsersApi.new(roster)
    scanner(api, cache_store: cache_store).scan
    scanner(api, cache_store: cache_store).scan(refresh: true)

    assert_equal 4, api.call_count
  end

  # A negative TTL expires the entry the instant it is written, which is the
  # only way to age the cache out inside a test without sleeping.
  def test_expired_cache_is_refetched
    api = PagedUsersApi.new(roster)
    scanner(api, cache_store: cache_store, ttl: -1).scan
    scanner(api, cache_store: cache_store, ttl: -1).scan

    assert_equal 4, api.call_count
  end

  def test_scan_works_without_a_cache_store
    report = scanner(PagedUsersApi.new(roster), cache_store: nil).scan

    assert_equal 3, report.deactivated_count
  end
end
