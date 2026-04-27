# frozen_string_literal: true

require 'test_helper'

class TargetResolverTest < Minitest::Test
  # Stand-in runner that wires fake APIs and fake workspace lookup
  class FakeRunner
    def initialize(conversations: nil, users: nil, workspaces: {})
      @conv = conversations
      @users = users
      @workspaces = workspaces
    end

    def conversations_api(_name)
      @conv
    end

    def users_api(_name)
      @users
    end

    def workspace(name)
      @workspaces[name] || @workspaces[:default]
    end
  end

  class FakeConversations
    def initialize(list_response: nil, open_response: nil)
      @list_response = list_response
      @open_response = open_response
    end

    def list
      @list_response || { 'channels' => [] }
    end

    def open(users:)
      @last_open_users = users
      @open_response || { 'ok' => true, 'channel' => { 'id' => 'D999' } }
    end

    attr_reader :last_open_users
  end

  class FakeUsers
    def initialize(list_response: nil)
      @list_response = list_response
    end

    def list
      @list_response || { 'members' => [] }
    end
  end

  # Minimal cache supporting target_resolver methods
  class FakeCache
    def initialize
      @channels = {}
      @users_by_id = {}
      @ids_by_name = {}
    end

    def get_channel_id(workspace, name)
      @channels["#{workspace}:#{name}"]
    end

    def set_channel(workspace, name, channel_id)
      @channels["#{workspace}:#{name}"] = channel_id
    end

    def get_user_id_by_name(workspace, name)
      @ids_by_name["#{workspace}:#{name}"]
    end

    def set_user(workspace, user_id, name, persist: false) # rubocop:disable Lint/UnusedMethodArgument
      @users_by_id["#{workspace}:#{user_id}"] = name
      @ids_by_name["#{workspace}:#{name}"] = user_id
    end
  end

  def setup
    @workspace = mock_workspace('ws1')
    @cache = FakeCache.new
  end

  # URL resolution
  def test_resolve_url_for_message
    runner = FakeRunner.new(workspaces: { 'workspace' => @workspace })
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)
    url = 'https://workspace.slack.com/archives/C123ABC/p1234567890123456'

    result = resolver.resolve(url, default_workspace: @workspace)

    assert_equal @workspace, result.workspace
    assert_equal 'C123ABC', result.channel_id
    assert_equal '1234567890.123456', result.msg_ts
    assert_nil result.thread_ts
  end

  def test_resolve_url_for_thread
    runner = FakeRunner.new(workspaces: { 'workspace' => @workspace })
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)
    url = 'https://workspace.slack.com/archives/C123ABC/p1234567890123456?thread_ts=1234567890.000111'

    result = resolver.resolve(url, default_workspace: @workspace)

    assert_equal 'C123ABC', result.channel_id
    assert_equal '1234567890.000111', result.thread_ts
    assert_nil result.msg_ts
  end

  def test_resolve_url_falls_through_when_parser_returns_nil
    # slack_url? returns true (contains 'slack.com/archives'), but parse returns nil
    # because URL doesn't match either URL_PATTERN. Falls through to non-URL handling
    # which then treats the string as a channel name and fetches via API.
    bad_url = 'https://example.slack.com/archives/notavalidid'
    @cache.set_channel(@workspace.name, bad_url, 'C0')
    runner = FakeRunner.new
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve(bad_url, default_workspace: @workspace)
    assert_equal 'C0', result.channel_id
  end

  def test_resolve_for_channel_id
    runner = FakeRunner.new
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('C123ABC', default_workspace: @workspace)

    assert_equal @workspace, result.workspace
    assert_equal 'C123ABC', result.channel_id
  end

  def test_resolve_for_dm_id
    runner = FakeRunner.new
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('D123ABC', default_workspace: @workspace)

    assert_equal 'D123ABC', result.channel_id
  end

  def test_resolve_for_group_id
    runner = FakeRunner.new
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('G123ABC', default_workspace: @workspace)

    assert_equal 'G123ABC', result.channel_id
  end

  # Channel name resolution
  def test_resolve_channel_uses_cache_when_present
    @cache.set_channel(@workspace.name, 'general', 'C111')
    runner = FakeRunner.new
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('general', default_workspace: @workspace)

    assert_equal 'C111', result.channel_id
  end

  def test_resolve_channel_strips_hash_prefix
    @cache.set_channel(@workspace.name, 'general', 'C222')
    runner = FakeRunner.new
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('#general', default_workspace: @workspace)

    assert_equal 'C222', result.channel_id
  end

  def test_resolve_channel_fetches_when_not_cached
    conversations = FakeConversations.new(
      list_response: { 'channels' => [{ 'id' => 'C333', 'name' => 'random' }] }
    )
    runner = FakeRunner.new(conversations: conversations)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('random', default_workspace: @workspace)

    assert_equal 'C333', result.channel_id
    # Should be cached now
    assert_equal 'C333', @cache.get_channel_id(@workspace.name, 'random')
  end

  def test_resolve_channel_raises_when_not_found
    conversations = FakeConversations.new(list_response: { 'channels' => [] })
    runner = FakeRunner.new(conversations: conversations)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    error = assert_raises(Slk::ConfigError) do
      resolver.resolve('nonexistent', default_workspace: @workspace)
    end

    assert_match(/Channel not found: #nonexistent/, error.message)
  end

  def test_resolve_channel_handles_nil_channels_list
    conversations = FakeConversations.new(list_response: { 'channels' => nil })
    runner = FakeRunner.new(conversations: conversations)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    assert_raises(Slk::ConfigError) do
      resolver.resolve('foo', default_workspace: @workspace)
    end
  end

  # DM resolution
  def test_resolve_dm_uses_cached_user_id
    @cache.set_user(@workspace.name, 'U1', 'jane')
    conversations = FakeConversations.new(
      open_response: { 'channel' => { 'id' => 'D777' } }
    )
    runner = FakeRunner.new(conversations: conversations)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('@jane', default_workspace: @workspace)

    assert_equal 'D777', result.channel_id
  end

  def test_resolve_dm_fetches_user_when_not_cached
    users = FakeUsers.new(list_response: {
                            'members' => [{
                              'id' => 'U2',
                              'name' => 'bob',
                              'profile' => { 'display_name' => 'Bob', 'real_name' => 'Robert' }
                            }]
                          })
    conversations = FakeConversations.new(open_response: { 'channel' => { 'id' => 'D888' } })
    runner = FakeRunner.new(conversations: conversations, users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('@Bob', default_workspace: @workspace)

    assert_equal 'D888', result.channel_id
  end

  def test_resolve_dm_finds_user_by_name_field
    users = FakeUsers.new(list_response: {
                            'members' => [{
                              'id' => 'U3', 'name' => 'alice', 'profile' => {}
                            }]
                          })
    conversations = FakeConversations.new(open_response: { 'channel' => { 'id' => 'D1' } })
    runner = FakeRunner.new(conversations: conversations, users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('@alice', default_workspace: @workspace)

    assert_equal 'D1', result.channel_id
  end

  def test_resolve_dm_finds_user_by_real_name
    users = FakeUsers.new(list_response: {
                            'members' => [{
                              'id' => 'U4', 'name' => 'x',
                              'profile' => { 'display_name' => '', 'real_name' => 'Real Person' }
                            }]
                          })
    conversations = FakeConversations.new(open_response: { 'channel' => { 'id' => 'D2' } })
    runner = FakeRunner.new(conversations: conversations, users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    result = resolver.resolve('@Real Person', default_workspace: @workspace)

    assert_equal 'D2', result.channel_id
  end

  def test_resolve_dm_raises_when_user_not_found
    users = FakeUsers.new(list_response: { 'members' => [] })
    runner = FakeRunner.new(users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    error = assert_raises(Slk::ConfigError) do
      resolver.resolve('@nobody', default_workspace: @workspace)
    end

    assert_match(/User not found: @nobody/, error.message)
  end

  def test_resolve_dm_handles_nil_members_list
    users = FakeUsers.new(list_response: { 'members' => nil })
    runner = FakeRunner.new(users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    assert_raises(Slk::ConfigError) do
      resolver.resolve('@nobody', default_workspace: @workspace)
    end
  end

  def test_extract_display_name_falls_back_to_real_name_when_display_blank
    users = FakeUsers.new(list_response: {
                            'members' => [{
                              'id' => 'U5', 'name' => 'x',
                              'profile' => { 'display_name' => '', 'real_name' => 'Realio' }
                            }]
                          })
    conversations = FakeConversations.new(open_response: { 'channel' => { 'id' => 'D3' } })
    runner = FakeRunner.new(conversations: conversations, users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    resolver.resolve('@Realio', default_workspace: @workspace)

    # Should have cached with real_name as the display name
    assert_equal 'U5', @cache.get_user_id_by_name(@workspace.name, 'Realio')
  end

  def test_extract_display_name_falls_back_to_name_when_profile_blank
    users = FakeUsers.new(list_response: {
                            'members' => [{
                              'id' => 'U6', 'name' => 'fallbackname', 'profile' => {}
                            }]
                          })
    conversations = FakeConversations.new(open_response: { 'channel' => { 'id' => 'D4' } })
    runner = FakeRunner.new(conversations: conversations, users: users)
    resolver = Slk::Services::TargetResolver.new(runner: runner, cache_store: @cache)

    resolver.resolve('@fallbackname', default_workspace: @workspace)

    assert_equal 'U6', @cache.get_user_id_by_name(@workspace.name, 'fallbackname')
  end
end
