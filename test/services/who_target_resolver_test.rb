# frozen_string_literal: true

require 'test_helper'

class WhoTargetResolverTest < Minitest::Test
  def setup
    @api = MockApiClient.new
    @workspace = mock_workspace
    @cache = FakeCacheStore.new
    @output = test_output
  end

  def resolver(options = {})
    Slk::Services::WhoTargetResolver.new(
      workspace: @workspace, cache_store: @cache,
      api_client: @api, output: @output, options: options
    )
  end

  def stub_list(members)
    @api.stub('users.list', { 'ok' => true, 'members' => members })
  end

  def list_user(id, name)
    {
      'id' => id, 'name' => name,
      'profile' => { 'real_name' => name, 'display_name' => name }
    }
  end

  def test_returns_self_for_nil_target
    @cache.set_meta(@workspace.name, 'self_user_id', 'UME')
    assert_equal ['UME'], resolver.resolve(nil)
    assert_equal ['UME'], resolver.resolve('me')
  end

  def test_self_user_id_falls_back_to_auth_test_when_uncached
    @api.stub('auth.test', { 'ok' => true, 'user_id' => 'UME' })
    assert_equal ['UME'], resolver.resolve(nil)
    assert_equal 'UME', @cache.get_meta(@workspace.name, 'self_user_id')
  end

  def test_returns_raw_user_id_unchanged
    assert_equal ['U123ABC'], resolver.resolve('U123ABC')
    assert_equal ['W123ABC'], resolver.resolve('W123ABC')
  end

  def test_strips_leading_at_from_name
    stub_list([list_user('U1', 'alice')])
    assert_equal ['U1'], resolver.resolve('@alice')
  end

  def test_raises_when_name_resolves_to_nothing
    stub_list([])
    assert_raises(Slk::ApiError) { resolver.resolve('ghost') }
  end

  def test_falls_back_to_cached_name_lookup_when_users_list_misses
    stub_list([])
    @cache.set_user(@workspace.name, 'U42', 'cachedname')
    assert_equal ['U42'], resolver.resolve('cachedname')
  end

  def test_all_returns_every_match
    stub_list([list_user('U1', 'alice'), list_user('U2', 'alice')])
    assert_equal %w[U1 U2], resolver(all: true).resolve('alice')
  end

  def test_pick_selects_specific_match_by_index
    stub_list([list_user('U1', 'alice'), list_user('U2', 'alice')])
    assert_equal ['U2'], resolver(pick: 2).resolve('alice')
  end

  def test_pick_out_of_range_raises
    stub_list([list_user('U1', 'alice'), list_user('U2', 'alice')])
    err = assert_raises(Slk::ApiError) { resolver(pick: 5).resolve('alice') }
    assert_match(/--pick 5 out of range/, err.message)
  end

  def test_propagates_api_errors_from_users_list
    @api.define_singleton_method(:post) { |*| raise Slk::ApiError, 'Network error: timeout' }
    err = assert_raises(Slk::ApiError) { resolver.resolve('alice') }
    assert_match(/Network error/, err.message)
  end

  # Minimal CacheStore stand-in.
  class FakeCacheStore
    def initialize
      @meta = {}
      @users = {}
    end

    def get_meta(workspace, key)
      @meta.dig(workspace, key, 'value')
    end

    def set_meta(workspace, key, value, persist: false) # rubocop:disable Lint/UnusedMethodArgument
      @meta[workspace] ||= {}
      @meta[workspace][key] = { 'value' => value }
      value
    end

    def each_meta(workspace)
      (@meta[workspace] || {}).each
    end

    def get_user(workspace, user_id)
      @users.dig(workspace, user_id)
    end

    def set_user(workspace, user_id, name, persist: false) # rubocop:disable Lint/UnusedMethodArgument
      @users[workspace] ||= {}
      @users[workspace][user_id] = name
    end

    def get_user_id_by_name(workspace, name)
      (@users[workspace] || {}).find { |_id, n| n == name }&.first
    end
  end
end
