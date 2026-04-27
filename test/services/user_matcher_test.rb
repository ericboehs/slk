# frozen_string_literal: true

require 'test_helper'

class UserMatcherTest < Minitest::Test
  def setup
    @api = MockApiClient.new
    @workspace = mock_workspace
    @cache = FakeCacheStore.new
  end

  def matcher
    Slk::Services::UserMatcher.new(
      api_client: @api, workspace: @workspace, cache_store: @cache
    )
  end

  def stub_list(members)
    @api.stub('users.list', { 'ok' => true, 'members' => members })
  end

  def list_user(id:, **attrs)
    profile = {
      'display_name' => attrs[:display], 'real_name' => attrs[:real],
      'first_name' => attrs[:first], 'last_name' => attrs[:last]
    }
    { 'id' => id, 'name' => attrs[:name], 'deleted' => attrs[:deleted] || false, 'profile' => profile }
  end

  def test_returns_empty_for_blank_name
    stub_list([list_user(id: 'U1', display: 'Alice')])
    assert_empty matcher.find_all('')
    assert_empty matcher.find_all(nil)
  end

  def test_finds_match_by_display_name_case_insensitively
    stub_list([list_user(id: 'U1', display: 'Alice')])
    matches = matcher.find_all('alice')
    assert_equal(['U1'], matches.map { |u| u['id'] })
  end

  def test_finds_match_by_first_plus_last_name
    stub_list([list_user(id: 'U1', display: 'Nick D', first: 'Nicholas', last: 'Dykzeul')])
    matches = matcher.find_all('Nicholas Dykzeul')
    assert_equal(['U1'], matches.map { |u| u['id'] })
  end

  def test_returns_multiple_matches
    stub_list([
                list_user(id: 'U1', real: 'Nicholas Dykzeul', deleted: true),
                list_user(id: 'U2', real: 'Nicholas Dykzeul')
              ])
    matches = matcher.find_all('Nicholas Dykzeul')
    assert_equal(%w[U1 U2], matches.map { |u| u['id'] })
  end

  def test_includes_cached_profile_users
    stub_list([])
    @cache.set_meta(@workspace.name, 'ui_U99', {
                      'user' => { 'id' => 'U99', 'profile' => { 'real_name' => 'Connect User' } }
                    })
    matches = matcher.find_all('Connect User')
    assert_equal(['U99'], matches.map { |u| u['id'] })
  end

  def test_dedupes_when_user_appears_in_both_sources
    stub_list([list_user(id: 'U1', real: 'Alice')])
    @cache.set_meta(@workspace.name, 'ui_U1', {
                      'user' => { 'id' => 'U1', 'profile' => { 'real_name' => 'Alice' } }
                    })
    matches = matcher.find_all('Alice')
    assert_equal 1, matches.size
  end

  def test_skips_non_ui_meta_keys
    stub_list([])
    @cache.set_meta(@workspace.name, 'team_profile_schema', { 'random' => 'data' })
    @cache.set_meta(@workspace.name, 'self_user_id', 'UME')
    assert_empty matcher.find_all('anything')
  end

  def test_propagates_api_errors_instead_of_returning_empty
    @api.define_singleton_method(:post) { |*| raise Slk::ApiError, 'Network error: timeout' }
    assert_raises(Slk::ApiError) { matcher.find_all('alice') }
  end

  def test_returns_empty_when_api_client_is_nil
    matcher = Slk::Services::UserMatcher.new(
      api_client: nil, workspace: @workspace, cache_store: @cache
    )
    assert_empty matcher.find_all('alice')
  end

  def test_skips_cache_lookup_when_cache_does_not_respond_to_each_meta
    bare_cache = Object.new
    matcher = Slk::Services::UserMatcher.new(
      api_client: @api, workspace: @workspace, cache_store: bare_cache
    )
    stub_list([list_user(id: 'U1', display: 'Bob')])
    assert_equal(['U1'], matcher.find_all('bob').map { |u| u['id'] })
  end

  def test_ignores_meta_entries_without_user_hash
    stub_list([])
    @cache.set_meta(@workspace.name, 'ui_U99', { 'random' => 'no user' })
    assert_empty matcher.find_all('anything')
  end

  def test_ignores_user_hash_without_id
    stub_list([])
    @cache.set_meta(@workspace.name, 'ui_U99', { 'user' => { 'profile' => { 'real_name' => 'NoId' } } })
    assert_empty matcher.find_all('NoId')
  end

  def test_skip_meta_when_value_is_not_hash
    stub_list([])
    fake = Object.new
    fake.define_singleton_method(:each_meta) { |_w| [%w[ui_U1 string-value]].each }
    matcher = Slk::Services::UserMatcher.new(
      api_client: @api, workspace: @workspace, cache_store: fake
    )
    assert_empty matcher.find_all('alice')
  end

  # Minimal fake of CacheStore covering only what UserMatcher needs.
  class FakeCacheStore
    def initialize
      @meta = {}
    end

    def each_meta(workspace_name)
      (@meta[workspace_name] || {}).each
    end

    def set_meta(workspace_name, key, value)
      @meta[workspace_name] ||= {}
      @meta[workspace_name][key] = { 'value' => value, 'fetched_at' => Time.now.to_i }
    end
  end
end
