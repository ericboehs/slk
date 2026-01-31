# frozen_string_literal: true

require 'test_helper'

class UserLookupTest < Minitest::Test
  def test_resolve_name_returns_nil_for_empty_user_id
    with_temp_config do
      lookup = build_lookup
      assert_nil lookup.resolve_name('')
      assert_nil lookup.resolve_name(nil)
    end
  end

  def test_resolve_name_returns_cached_name
    with_temp_config do
      cache = Slk::Services::CacheStore.new
      cache.set_user('test', 'U123ABC', 'John Doe')

      lookup = build_lookup(cache: cache)
      assert_equal 'John Doe', lookup.resolve_name('U123ABC')
    end
  end

  def test_resolve_name_fetches_from_api_on_cache_miss
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.info', {
                        'ok' => true,
                        'user' => {
                          'id' => 'U123ABC',
                          'name' => 'jdoe',
                          'profile' => {
                            'display_name' => 'John Doe',
                            'real_name' => 'John Q. Doe'
                          }
                        }
                      })

      cache = Slk::Services::CacheStore.new
      lookup = build_lookup(cache: cache, api_client: api_client)

      assert_equal 'John Doe', lookup.resolve_name('U123ABC')
      # Verify it was cached
      assert_equal 'John Doe', cache.get_user('test', 'U123ABC')
    end
  end

  def test_resolve_name_uses_real_name_when_display_name_empty
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.info', {
                        'ok' => true,
                        'user' => {
                          'id' => 'U123ABC',
                          'name' => 'jdoe',
                          'profile' => {
                            'display_name' => '',
                            'real_name' => 'John Q. Doe'
                          }
                        }
                      })

      lookup = build_lookup(api_client: api_client)
      assert_equal 'John Q. Doe', lookup.resolve_name('U123ABC')
    end
  end

  def test_resolve_name_uses_name_when_both_empty
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.info', {
                        'ok' => true,
                        'user' => {
                          'id' => 'U123ABC',
                          'name' => 'jdoe',
                          'profile' => {
                            'display_name' => '',
                            'real_name' => ''
                          }
                        }
                      })

      lookup = build_lookup(api_client: api_client)
      assert_equal 'jdoe', lookup.resolve_name('U123ABC')
    end
  end

  def test_resolve_name_returns_nil_when_api_fails
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.info', { 'ok' => false })

      lookup = build_lookup(api_client: api_client)
      assert_nil lookup.resolve_name('U123ABC')
    end
  end

  def test_resolve_name_returns_nil_without_api_client
    with_temp_config do
      lookup = build_lookup(api_client: nil)
      assert_nil lookup.resolve_name('U123ABC')
    end
  end

  def test_resolve_name_handles_api_error_gracefully
    with_temp_config do
      api_client = ErrorRaisingApiClient.new
      debug_messages = []

      lookup = build_lookup(
        api_client: api_client,
        on_debug: ->(msg) { debug_messages << msg }
      )

      assert_nil lookup.resolve_name('U123ABC')
      assert_equal 1, debug_messages.size
      assert_match(/User lookup failed/, debug_messages.first)
    end
  end

  def test_resolve_name_or_bot_handles_bot_ids
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('bots.info', {
                        'ok' => true,
                        'bot' => {
                          'id' => 'B123ABC',
                          'name' => 'Test Bot'
                        }
                      })

      cache = Slk::Services::CacheStore.new
      lookup = build_lookup(cache: cache, api_client: api_client)

      assert_equal 'Test Bot', lookup.resolve_name_or_bot('B123ABC')
      # Verify it was cached
      assert_equal 'Test Bot', cache.get_user('test', 'B123ABC')
    end
  end

  def test_resolve_name_or_bot_handles_user_ids
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.info', {
                        'ok' => true,
                        'user' => {
                          'id' => 'U123ABC',
                          'name' => 'jdoe',
                          'profile' => { 'display_name' => 'John Doe' }
                        }
                      })

      lookup = build_lookup(api_client: api_client)
      assert_equal 'John Doe', lookup.resolve_name_or_bot('U123ABC')
    end
  end

  def test_find_id_by_name_returns_nil_for_empty_name
    with_temp_config do
      lookup = build_lookup
      assert_nil lookup.find_id_by_name('')
      assert_nil lookup.find_id_by_name(nil)
    end
  end

  def test_find_id_by_name_returns_cached_id
    with_temp_config do
      cache = Slk::Services::CacheStore.new
      cache.set_user('test', 'U123ABC', 'John Doe')

      lookup = build_lookup(cache: cache)
      assert_equal 'U123ABC', lookup.find_id_by_name('John Doe')
    end
  end

  def test_find_id_by_name_fetches_from_api_on_cache_miss
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.list', {
                        'ok' => true,
                        'members' => [
                          {
                            'id' => 'U123ABC',
                            'name' => 'jdoe',
                            'profile' => {
                              'display_name' => 'John Doe',
                              'real_name' => 'John Q. Doe'
                            }
                          },
                          {
                            'id' => 'U456DEF',
                            'name' => 'jane',
                            'profile' => { 'display_name' => 'Jane Smith' }
                          }
                        ]
                      })

      cache = Slk::Services::CacheStore.new
      lookup = build_lookup(cache: cache, api_client: api_client)

      assert_equal 'U123ABC', lookup.find_id_by_name('John Doe')
      # Verify the found user was cached
      assert_equal 'John Doe', cache.get_user('test', 'U123ABC')
    end
  end

  def test_find_id_by_name_matches_by_username
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.list', {
                        'ok' => true,
                        'members' => [
                          {
                            'id' => 'U123ABC',
                            'name' => 'jdoe',
                            'profile' => { 'display_name' => '' }
                          }
                        ]
                      })

      lookup = build_lookup(api_client: api_client)
      assert_equal 'U123ABC', lookup.find_id_by_name('jdoe')
    end
  end

  def test_find_id_by_name_matches_by_real_name
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.list', {
                        'ok' => true,
                        'members' => [
                          {
                            'id' => 'U123ABC',
                            'name' => 'jdoe',
                            'profile' => {
                              'display_name' => '',
                              'real_name' => 'John Q. Doe'
                            }
                          }
                        ]
                      })

      lookup = build_lookup(api_client: api_client)
      assert_equal 'U123ABC', lookup.find_id_by_name('John Q. Doe')
    end
  end

  def test_find_id_by_name_returns_nil_when_not_found
    with_temp_config do
      api_client = MockApiClient.new
      api_client.stub('users.list', { 'ok' => true, 'members' => [] })

      lookup = build_lookup(api_client: api_client)
      assert_nil lookup.find_id_by_name('Unknown User')
    end
  end

  private

  def build_lookup(cache: nil, api_client: nil, on_debug: nil)
    Slk::Services::UserLookup.new(
      cache_store: cache || Slk::Services::CacheStore.new,
      workspace: mock_workspace,
      api_client: api_client,
      on_debug: on_debug
    )
  end

  # Mock API client that raises errors
  class ErrorRaisingApiClient
    def post_form(_workspace, _method, _params = {})
      raise Slk::ApiError, 'API error'
    end
  end
end
