# frozen_string_literal: true

require 'test_helper'

class ActivityEnricherTest < Minitest::Test
  def setup
    @cache = FakeCacheStore.new
    @conversations = FakeConversationsApi.new
    @workspace = mock_workspace('test')
  end

  def test_enrich_all_dups_items
    items = [{ 'item' => { 'type' => 'unknown' } }]
    enricher = build
    result = enricher.enrich_all(items, @workspace)
    refute_same items.first, result.first
  end

  def test_unknown_type_calls_debug
    debug_msgs = []
    enricher = build(on_debug: ->(m) { debug_msgs << m })
    enricher.enrich_all([{ 'item' => { 'type' => 'mystery' } }], @workspace)
    assert(debug_msgs.any? { |m| m.include?('Unknown activity type') })
  end

  def test_nil_type_does_nothing
    debug_msgs = []
    enricher = build(on_debug: ->(m) { debug_msgs << m })
    enricher.enrich_all([{ 'item' => {} }], @workspace)
    assert_empty debug_msgs
  end

  def test_resolve_user_uses_cache
    @cache.users[%w[test U1]] = 'alice'
    enricher = build
    assert_equal 'alice', enricher.resolve_user(@workspace, 'U1')
  end

  def test_resolve_user_falls_back_to_id
    enricher = build
    assert_equal 'U_unknown', enricher.resolve_user(@workspace, 'U_unknown')
  end

  def test_resolve_channel_dm_prefix
    assert_equal 'DM', build.resolve_channel(@workspace, 'D123')
  end

  def test_resolve_channel_group_prefix
    assert_equal 'Group DM', build.resolve_channel(@workspace, 'G123')
  end

  def test_resolve_channel_uses_cache_when_present
    @cache.channels[%w[test C1]] = 'general'
    assert_equal '#general', build.resolve_channel(@workspace, 'C1')
  end

  def test_resolve_channel_strips_hash_when_requested
    @cache.channels[%w[test C1]] = 'general'
    assert_equal 'general', build.resolve_channel(@workspace, 'C1', with_hash: false)
  end

  def test_resolve_channel_fetches_from_api_and_caches
    @conversations.info_response = { 'ok' => true, 'channel' => { 'name' => 'general' } }
    enricher = build
    assert_equal '#general', enricher.resolve_channel(@workspace, 'C1')
    # second call uses cache
    @conversations.info_response = nil
    assert_equal '#general', enricher.resolve_channel(@workspace, 'C1')
  end

  def test_resolve_channel_returns_id_when_api_fails_ok_false
    @conversations.info_response = { 'ok' => false }
    assert_equal 'C1', build.resolve_channel(@workspace, 'C1')
  end

  def test_resolve_channel_handles_api_error_with_debug
    @conversations.raise_on_info = Slk::ApiError.new('not found', code: :error)
    msgs = []
    enricher = build(on_debug: ->(m) { msgs << m })
    assert_equal 'C1', enricher.resolve_channel(@workspace, 'C1')
    assert(msgs.any? { |m| m.include?('Could not resolve channel C1') })
  end

  # message_reaction
  def test_enrich_reaction_resolves_user_and_channel
    @cache.users[%w[test U1]] = 'bob'
    @cache.channels[%w[test C1]] = 'general'
    item = { 'item' => { 'type' => 'message_reaction',
                         'reaction' => { 'user' => 'U1' },
                         'message' => { 'channel' => 'C1' } } }
    result = build.enrich_all([item], @workspace).first
    assert_equal 'bob', result['item']['reaction']['user_name']
    assert_equal 'general', result['item']['message']['channel_name']
  end

  def test_enrich_reaction_missing_data_calls_debug
    msgs = []
    enricher = build(on_debug: ->(m) { msgs << m })
    enricher.enrich_all([{ 'item' => { 'type' => 'message_reaction' } }], @workspace)
    assert(msgs.any? { |m| m.include?('Could not enrich reaction') })
  end

  # mention
  def test_enrich_mention_uses_author_user_id
    @cache.users[%w[test U2]] = 'carol'
    @cache.channels[%w[test C2]] = 'random'
    item = { 'item' => { 'type' => 'at_user',
                         'message' => { 'author_user_id' => 'U2', 'channel' => 'C2' } } }
    result = build.enrich_all([item], @workspace).first
    assert_equal 'carol', result['item']['message']['user_name']
    assert_equal 'random', result['item']['message']['channel_name']
  end

  def test_enrich_mention_uses_user_field_fallback
    @cache.users[%w[test U3]] = 'dave'
    item = { 'item' => { 'type' => 'at_channel',
                         'message' => { 'user' => 'U3', 'channel' => 'C3' } } }
    @cache.channels[%w[test C3]] = 'eng'
    result = build.enrich_all([item], @workspace).first
    assert_equal 'dave', result['item']['message']['user_name']
  end

  def test_enrich_mention_missing_message_calls_debug
    msgs = []
    enricher = build(on_debug: ->(m) { msgs << m })
    enricher.enrich_all([{ 'item' => { 'type' => 'at_everyone' } }], @workspace)
    assert(msgs.any? { |m| m.include?('Could not enrich mention') })
  end

  # thread
  def test_enrich_thread_resolves_channel
    @cache.channels[%w[test C7]] = 'th'
    item = { 'item' => { 'type' => 'thread_v2',
                         'bundle_info' => { 'payload' => { 'thread_entry' => { 'channel_id' => 'C7' } } } } }
    result = build.enrich_all([item], @workspace).first
    assert_equal 'th', result['item']['bundle_info']['payload']['thread_entry']['channel_name']
  end

  def test_enrich_thread_missing_payload_calls_debug
    msgs = []
    enricher = build(on_debug: ->(m) { msgs << m })
    enricher.enrich_all([{ 'item' => { 'type' => 'thread_v2' } }], @workspace)
    assert(msgs.any? { |m| m.include?('Could not enrich thread') })
  end

  # bot_dm_bundle
  def test_enrich_bot_dm_resolves_channel
    @cache.channels[%w[test C9]] = 'botz'
    item = { 'item' => { 'type' => 'bot_dm_bundle',
                         'bundle_info' => { 'payload' => { 'message' => { 'channel' => 'C9' } } } } }
    result = build.enrich_all([item], @workspace).first
    assert_equal 'botz', result['item']['bundle_info']['payload']['message']['channel_name']
  end

  def test_enrich_reaction_with_only_reaction_no_message
    msgs = []
    enricher = build(on_debug: ->(m) { msgs << m })
    item = { 'item' => { 'type' => 'message_reaction', 'reaction' => { 'user' => 'U1' } } }
    enricher.enrich_all([item], @workspace)
    assert(msgs.any? { |m| m.include?('Could not enrich reaction') })
  end

  def test_enrich_user_handles_nil_path_data
    enricher = build
    item = {}
    enricher.send(:enrich_user, item, %w[missing], 'user', @workspace)
    assert_empty item
  end

  def test_enrich_channel_handles_nil_path_data
    enricher = build
    item = {}
    enricher.send(:enrich_channel, item, %w[missing], 'channel', @workspace)
    assert_empty item
  end

  def test_enrich_reaction_missing_user_id_skips
    item = { 'item' => { 'type' => 'message_reaction',
                         'reaction' => {}, 'message' => {} } }
    result = build.enrich_all([item], @workspace).first
    refute result['item']['reaction'].key?('user_name')
  end

  def test_resolve_channel_api_error_without_on_debug
    @conversations.raise_on_info = Slk::ApiError.new('boom', code: :error)
    enricher = build
    assert_equal 'C1', enricher.resolve_channel(@workspace, 'C1')
  end

  def test_unknown_type_without_on_debug
    enricher = build
    enricher.enrich_all([{ 'item' => { 'type' => 'mystery' } }], @workspace)
  end

  def test_missing_data_without_on_debug
    enricher = build
    enricher.enrich_all([{ 'item' => { 'type' => 'message_reaction' } }], @workspace)
  end

  def test_enrich_bot_dm_missing_payload_calls_debug
    msgs = []
    enricher = build(on_debug: ->(m) { msgs << m })
    enricher.enrich_all([{ 'item' => { 'type' => 'bot_dm_bundle' } }], @workspace)
    assert(msgs.any? { |m| m.include?('Could not enrich bot DM') })
  end

  private

  def build(on_debug: nil)
    Slk::Services::ActivityEnricher.new(
      cache_store: @cache, conversations_api: @conversations, on_debug: on_debug
    )
  end

  class FakeCacheStore
    attr_reader :users, :channels

    def initialize
      @users = {}
      @channels = {}
    end

    def get_user(workspace, id)
      @users[[workspace, id]]
    end

    def get_channel_name(workspace, id)
      @channels[[workspace, id]]
    end

    def set_channel(workspace, name, id)
      @channels[[workspace, id]] = name
    end
  end

  class FakeConversationsApi
    attr_accessor :info_response, :raise_on_info

    def info(channel:) # rubocop:disable Lint/UnusedMethodArgument
      raise @raise_on_info if @raise_on_info

      @info_response || { 'ok' => false }
    end
  end
end
