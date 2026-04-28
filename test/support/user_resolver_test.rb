# frozen_string_literal: true

require 'test_helper'

class UserResolverTest < Minitest::Test
  # Host class that includes UserResolver to satisfy the include contract
  class Host
    include Slk::Support::UserResolver

    attr_reader :runner, :cache_store, :debug_messages

    def initialize(runner, cache_store)
      @runner = runner
      @cache_store = cache_store
      @debug_messages = []
    end

    def debug(message)
      @debug_messages << message
    end
  end

  # Stand-in for runner that returns canned APIs
  class FakeRunner
    attr_reader :conversations_calls, :users_calls

    def initialize(conversations_api: nil, users_api: nil)
      @conv = conversations_api
      @users = users_api
      @conversations_calls = []
      @users_calls = []
    end

    def conversations_api(name)
      @conversations_calls << name
      @conv
    end

    def users_api(name)
      @users_calls << name
      @users
    end
  end

  # Stand-in for the conversations API
  class FakeConversations
    def initialize(responses = {})
      @responses = responses
      @raise_on = nil
    end

    attr_writer :raise_on

    def info(channel:)
      raise Slk::ApiError, 'boom' if @raise_on == channel

      @responses[channel] || { 'ok' => false }
    end
  end

  # Stand-in for the users API
  class FakeUsers
    def initialize(responses = {})
      @responses = responses
      @raise_on = nil
    end

    attr_writer :raise_on

    def info(user_id)
      raise Slk::ApiError, 'fail' if @raise_on == user_id

      @responses[user_id] || { 'ok' => false }
    end
  end

  # Simple in-memory cache double
  class FakeCache
    def initialize
      @users = {}
      @channels_by_id = {}
      @channels_by_name = {}
    end

    def get_user(workspace, user_id)
      @users["#{workspace}:#{user_id}"]
    end

    def set_user(workspace, user_id, name, persist: false) # rubocop:disable Lint/UnusedMethodArgument
      @users["#{workspace}:#{user_id}"] = name
    end

    def get_channel_name(workspace, channel_id)
      @channels_by_id["#{workspace}:#{channel_id}"]
    end

    def set_channel(workspace, name, channel_id)
      @channels_by_id["#{workspace}:#{channel_id}"] = name
      @channels_by_name["#{workspace}:#{name}"] = channel_id
    end
  end

  def setup
    @workspace = mock_workspace('ws1')
    @cache = FakeCache.new
  end

  # resolve_dm_user_name
  def test_resolve_dm_user_name_returns_channel_id_when_info_not_ok
    conversations = FakeConversations.new('D1' => { 'ok' => false })
    host = build_host(conversations: conversations)

    assert_equal 'D1', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  def test_resolve_dm_user_name_returns_channel_id_when_no_user
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => {} })
    host = build_host(conversations: conversations)

    assert_equal 'D1', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  def test_resolve_dm_user_name_returns_cached_user_name
    @cache.set_user(@workspace.name, 'U1', 'cachedname')
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    host = build_host(conversations: conversations)

    assert_equal 'cachedname', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  def test_resolve_dm_user_name_fetches_from_api_when_not_cached
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new(
      'U1' => { 'ok' => true, 'user' => { 'profile' => { 'display_name' => 'jane' } } }
    )
    host = build_host(conversations: conversations, users: users)

    assert_equal 'jane', host.resolve_dm_user_name(@workspace, 'D1', conversations)
    assert_equal 'jane', @cache.get_user(@workspace.name, 'U1')
  end

  def test_resolve_dm_user_name_falls_back_to_user_id_when_lookup_fails
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new('U1' => { 'ok' => false })
    host = build_host(conversations: conversations, users: users)

    assert_equal 'U1', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  def test_resolve_dm_user_name_returns_user_id_when_user_info_lookup_raises
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new
    users.raise_on = 'U1'
    host = build_host(conversations: conversations, users: users)

    assert_equal 'U1', host.resolve_dm_user_name(@workspace, 'D1', conversations)
    assert_match(/User lookup failed for U1/, host.debug_messages.first)
  end

  def test_resolve_dm_user_name_returns_user_id_when_name_extraction_returns_nil
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new('U1' => { 'ok' => true, 'user' => { 'profile' => {} } })
    host = build_host(conversations: conversations, users: users)

    assert_equal 'U1', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  def test_resolve_dm_user_name_rescues_dm_lookup_api_error
    conversations = FakeConversations.new
    conversations.raise_on = 'D1'
    host = build_host(conversations: conversations)

    assert_equal 'D1', host.resolve_dm_user_name(@workspace, 'D1', conversations)
    assert_match(/DM info lookup failed for D1/, host.debug_messages.first)
  end

  # resolve_conversation_label
  def test_resolve_conversation_label_for_dm_returns_at_username
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new(
      'U1' => { 'ok' => true, 'user' => { 'profile' => { 'real_name' => 'Real Name' } } }
    )
    host = build_host(conversations: conversations, users: users)

    assert_equal '@Real Name', host.resolve_conversation_label(@workspace, 'D1')
  end

  def test_resolve_conversation_label_for_cached_channel
    @cache.set_channel(@workspace.name, 'general', 'C1')
    host = build_host

    assert_equal '#general', host.resolve_conversation_label(@workspace, 'C1')
  end

  def test_resolve_conversation_label_fetches_channel_when_not_cached
    conversations = FakeConversations.new('C1' => { 'ok' => true, 'channel' => { 'name' => 'random' } })
    host = build_host(conversations: conversations)

    assert_equal '#random', host.resolve_conversation_label(@workspace, 'C1')
    assert_equal 'random', @cache.get_channel_name(@workspace.name, 'C1')
  end

  def test_resolve_conversation_label_returns_id_when_info_fails
    conversations = FakeConversations.new('C1' => { 'ok' => false })
    host = build_host(conversations: conversations)

    assert_equal '#C1', host.resolve_conversation_label(@workspace, 'C1')
  end

  def test_resolve_conversation_label_returns_id_when_name_missing
    conversations = FakeConversations.new('C1' => { 'ok' => true, 'channel' => {} })
    host = build_host(conversations: conversations)

    assert_equal '#C1', host.resolve_conversation_label(@workspace, 'C1')
  end

  def test_resolve_conversation_label_handles_api_error
    conversations = FakeConversations.new
    conversations.raise_on = 'C1'
    host = build_host(conversations: conversations)

    assert_equal '#C1', host.resolve_conversation_label(@workspace, 'C1')
    assert_match(/Channel info lookup failed for C1/, host.debug_messages.first)
  end

  # extract_user_from_message
  def test_extract_user_from_message_uses_user_profile_display_name
    msg = { 'user_profile' => { 'display_name' => 'Display' } }
    host = build_host

    assert_equal 'Display', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_falls_back_to_real_name_when_display_blank
    msg = { 'user_profile' => { 'display_name' => '', 'real_name' => 'Real' } }
    host = build_host

    assert_equal 'Real', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_returns_nil_from_profile_when_all_blank
    msg = { 'user_profile' => { 'display_name' => '', 'real_name' => '' }, 'username' => 'fallback' }
    host = build_host

    assert_equal 'fallback', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_uses_username
    msg = { 'username' => 'bot_name' }
    host = build_host

    assert_equal 'bot_name', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_skips_blank_username
    msg = { 'username' => '', 'user' => 'U1' }
    @cache.set_user(@workspace.name, 'U1', 'cached')
    host = build_host

    assert_equal 'cached', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_falls_back_to_cache
    msg = { 'user' => 'U2' }
    @cache.set_user(@workspace.name, 'U2', 'cached2')
    host = build_host

    assert_equal 'cached2', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_uses_bot_id_when_no_user
    msg = { 'bot_id' => 'B1' }
    @cache.set_user(@workspace.name, 'B1', 'BotName')
    host = build_host

    assert_equal 'BotName', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_returns_user_id_when_no_other_data
    msg = { 'user' => 'U99' }
    host = build_host

    assert_equal 'U99', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_returns_bot_id_when_only_bot_id
    msg = { 'bot_id' => 'B99' }
    host = build_host

    assert_equal 'B99', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_user_from_message_returns_unknown_when_nothing_set
    host = build_host

    assert_equal 'unknown', host.extract_user_from_message({}, @workspace)
  end

  def test_extract_user_from_message_returns_nil_from_cache_when_no_user_id
    msg = {}
    host = build_host

    # name_from_cache should return nil because user_id is nil; final fallback is 'unknown'
    assert_equal 'unknown', host.extract_user_from_message(msg, @workspace)
  end

  def test_user_profile_real_name_used_when_display_name_missing_key
    msg = { 'user_profile' => { 'real_name' => 'Bob' } }
    host = build_host

    assert_equal 'Bob', host.extract_user_from_message(msg, @workspace)
  end

  def test_extract_name_from_user_info_uses_real_name_then_name
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new(
      'U1' => { 'ok' => true, 'user' => { 'profile' => { 'display_name' => '' }, 'name' => 'fallback' } }
    )
    host = build_host(conversations: conversations, users: users)

    assert_equal 'fallback', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  def test_extract_name_from_user_info_uses_real_name_when_display_blank
    conversations = FakeConversations.new('D1' => { 'ok' => true, 'channel' => { 'user' => 'U1' } })
    users = FakeUsers.new(
      'U1' => { 'ok' => true,
                'user' => { 'profile' => { 'display_name' => '', 'real_name' => 'Realname' } } }
    )
    host = build_host(conversations: conversations, users: users)

    assert_equal 'Realname', host.resolve_dm_user_name(@workspace, 'D1', conversations)
  end

  private

  def build_host(conversations: nil, users: nil)
    runner = FakeRunner.new(conversations_api: conversations, users_api: users)
    Host.new(runner, @cache)
  end
end
