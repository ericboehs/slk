# frozen_string_literal: true

require 'test_helper'

class StartDateLookupTest < Minitest::Test
  FIELD_ID = 'Xf05START'

  def cache_store
    @cache_store ||= Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
  end

  # Counts profile calls, because the whole point of the cache is that they
  # are expensive.
  class FakeUsersApi
    attr_reader :requested

    def initialize(dates = {}, raise_for: nil)
      @dates = dates
      @raise_for = raise_for
      @requested = []
    end

    def profile_for(user_id)
      @requested << user_id
      raise Slk::ApiError.new('user_not_found', code: :user_not_found) if @raise_for == user_id

      value = @dates[user_id]
      fields = value ? { FIELD_ID => { 'value' => value, 'label' => 'Start Date' } } : {}
      { 'ok' => true, 'profile' => { 'fields' => fields } }
    end
  end

  class FakeField
    attr_reader :id

    def initialize(id = FIELD_ID) = @id = id
    def missing_message = 'no start date field here'
  end

  def lookup(api, field: FakeField.new, cache: nil, on_progress: nil)
    Slk::Services::StartDateLookup.new(
      users_api: api, field: field, workspace_name: 'test', cache_store: cache, on_progress: on_progress
    )
  end

  def test_fetch_returns_a_date_per_user
    api = FakeUsersApi.new({ 'U1' => '2020-01-15', 'U2' => '2018-06-01' })

    assert_equal({ 'U1' => '2020-01-15', 'U2' => '2018-06-01' }, lookup(api).fetch(%w[U1 U2]))
  end

  def test_an_account_with_no_start_date_maps_to_nil
    assert_equal({ 'U1' => nil }, lookup(FakeUsersApi.new).fetch(%w[U1]))
  end

  def test_no_users_means_no_calls
    api = FakeUsersApi.new

    assert_empty lookup(api).fetch([])
    assert_empty api.requested
  end

  def test_missing_field_raises_before_spending_a_call
    api = FakeUsersApi.new
    error = assert_raises(Slk::Services::StartDateLookup::MissingFieldError) do
      lookup(api, field: FakeField.new(nil)).fetch(%w[U1])
    end

    assert_equal 'no start date field here', error.message
    assert_empty api.requested
  end

  def test_cached_dates_are_not_fetched_again
    api = FakeUsersApi.new({ 'U1' => '2020-01-15' })
    lookup(api, cache: cache_store).fetch(%w[U1])
    second = FakeUsersApi.new({ 'U1' => '2020-01-15' })

    assert_equal({ 'U1' => '2020-01-15' }, lookup(second, cache: cache_store).fetch(%w[U1]))
    assert_empty second.requested
  end

  # Otherwise every run pays again to learn the same nothing.
  def test_accounts_with_no_date_are_cached_as_well
    lookup(FakeUsersApi.new, cache: cache_store).fetch(%w[U1])
    second = FakeUsersApi.new

    assert_equal({ 'U1' => nil }, lookup(second, cache: cache_store).fetch(%w[U1]))
    assert_empty second.requested
  end

  def test_only_the_unknown_users_cost_a_call
    lookup(FakeUsersApi.new({ 'U1' => '2020-01-15' }), cache: cache_store).fetch(%w[U1])
    second = FakeUsersApi.new({ 'U1' => '2020-01-15', 'U2' => '2021-02-02' })
    lookup(second, cache: cache_store).fetch(%w[U1 U2])

    assert_equal %w[U2], second.requested
  end

  # Interrupting a long lookup should keep the work already paid for.
  def test_each_answer_is_cached_as_it_arrives
    api = FakeUsersApi.new({ 'U1' => '2020-01-15', 'U2' => '2021-02-02', 'U3' => '2022-03-03' })
    assert_raises(Interrupt) do
      lookup(api, cache: cache_store, on_progress: lambda { |done, _total|
        raise Interrupt if done == 3
      }).fetch(%w[U1 U2 U3])
    end

    resumed = FakeUsersApi.new({ 'U3' => '2022-03-03' })
    lookup(resumed, cache: cache_store).fetch(%w[U1 U2 U3])

    assert_equal %w[U3], resumed.requested
  end

  def test_uncached_count_reports_what_the_next_fetch_would_cost
    lookup(FakeUsersApi.new({ 'U1' => '2020-01-15' }), cache: cache_store).fetch(%w[U1])

    assert_equal 2, lookup(FakeUsersApi.new, cache: cache_store).uncached_count(%w[U1 U2 U3])
  end

  def test_uncached_count_without_a_cache_counts_everything
    assert_equal 3, lookup(FakeUsersApi.new).uncached_count(%w[U1 U2 U3])
  end

  def test_progress_reports_position_and_total
    seen = []
    lookup(FakeUsersApi.new, on_progress: ->(done, total) { seen << [done, total] }).fetch(%w[U1 U2])

    assert_equal [[1, 2], [2, 2]], seen
  end

  def test_progress_is_silent_for_users_already_cached
    lookup(FakeUsersApi.new({ 'U1' => '2020-01-15' }), cache: cache_store).fetch(%w[U1])
    seen = []
    lookup(FakeUsersApi.new, cache: cache_store, on_progress: ->(d, t) { seen << [d, t] }).fetch(%w[U1])

    assert_empty seen
  end

  def test_only_the_requested_users_come_back
    lookup(FakeUsersApi.new({ 'U1' => '2020-01-15', 'U2' => '2021-02-02' }), cache: cache_store).fetch(%w[U1 U2])

    assert_equal %w[U2], lookup(FakeUsersApi.new, cache: cache_store).fetch(%w[U2]).keys
  end

  def test_a_profile_without_a_fields_hash_is_not_a_crash
    api = Object.new
    def api.profile_for(_id) = { 'ok' => true, 'profile' => { 'fields' => [] } }

    assert_equal({ 'U1' => nil }, lookup(api).fetch(%w[U1]))
  end

  def test_an_empty_string_counts_as_no_date
    assert_equal({ 'U1' => nil }, lookup(FakeUsersApi.new({ 'U1' => '' })).fetch(%w[U1]))
  end

  def test_an_api_error_on_one_profile_stops_the_run
    api = FakeUsersApi.new({ 'U1' => '2020-01-15' }, raise_for: 'U2')

    assert_raises(Slk::ApiError) { lookup(api, cache: cache_store).fetch(%w[U1 U2]) }
    assert_equal({ 'U1' => '2020-01-15' }, lookup(FakeUsersApi.new, cache: cache_store).fetch(%w[U1]))
  end

  def test_works_without_a_cache_store
    api = FakeUsersApi.new({ 'U1' => '2020-01-15' })

    assert_equal({ 'U1' => '2020-01-15' }, lookup(api).fetch(%w[U1]))
  end
end
