# frozen_string_literal: true

require 'test_helper'

class GroupDmLabelTest < Minitest::Test
  def setup
    @client = MockApiClient.new
    @workspace = mock_workspace('oddball')
    @cache = Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
    @runner = Slk::Runner.new(output: test_output, api_client: @client, cache_store: @cache)
    workspace = @workspace
    @runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    @debug = []
    @client.stub('auth.test', { 'ok' => true, 'user_id' => 'USELF' })
  end

  def test_named_group_dm_shows_its_name
    stub_info('name' => 'ifams review', 'properties' => { 'has_custom_mpdm_name' => true })

    assert_equal '#ifams review', labeler.label(@workspace, 'C0C8TMPUV3P')
  end

  def test_unnamed_group_dm_lists_everyone_but_you
    stub_info('name' => 'mpdm-ada--eric--grace-1', 'members' => %w[U2 USELF U3])
    @cache.set_user('oddball', 'U2', 'Ada Lovelace')
    @cache.set_user('oddball', 'U3', 'Grace Hopper')

    assert_equal '@Ada Lovelace, Grace Hopper', labeler.label(@workspace, 'G1')
    assert_equal 'USELF', @cache.get_meta('oddball', 'self_user_id')
  end

  def test_cached_self_id_skips_auth_test
    @cache.set_meta('oddball', 'self_user_id', 'USELF')
    stub_info('name' => 'mpdm-ada--eric-1', 'members' => %w[USELF U2])
    @cache.set_user('oddball', 'U2', 'Ada Lovelace')

    assert_equal '@Ada Lovelace', labeler.label(@workspace, 'G1')
    refute(@client.calls.any? { |c| c[:method] == 'auth.test' })
  end

  def test_failed_self_lookup_keeps_every_member
    @client.stub('auth.test', Slk::ApiError.new('invalid_auth'))
    stub_info('name' => 'mpdm-ada--eric-1', 'members' => %w[USELF U2])
    @cache.set_user('oddball', 'USELF', 'Eric')
    @cache.set_user('oddball', 'U2', 'Ada Lovelace')

    assert_equal '@Eric, Ada Lovelace', labeler.label(@workspace, 'G1')
    assert_match(/Could not identify self/, @debug.first)
  end

  def test_no_members_falls_back_to_slack_name
    stub_info('name' => 'mpdm-ada--eric-1')

    assert_equal '#mpdm-ada--eric-1', labeler.label(@workspace, 'G1')
  end

  def test_lookup_failure_falls_back_to_id
    @client.stub('conversations.info', Slk::ApiError.new('channel_not_found'))

    assert_equal '#G404', labeler.label(@workspace, 'G404')
    assert_match(/channel_not_found/, @debug.first)
  end

  def test_empty_info_falls_back_to_id
    @client.stub('conversations.info', { 'ok' => true })

    assert_equal '#G1', labeler.label(@workspace, 'G1')
  end

  def test_label_is_remembered_per_channel
    stub_info('name' => 'ifams review')
    label = labeler

    2.times { label.label(@workspace, 'C0C8TMPUV3P') }

    assert_equal(1, @client.calls.count { |c| c[:method] == 'conversations.info' })
  end

  private

  def stub_info(channel)
    @client.stub('conversations.info', { 'ok' => true, 'channel' => { 'is_mpim' => true }.merge(channel) })
  end

  def labeler
    Slk::Services::GroupDmLabel.new(runner: @runner, on_debug: ->(message) { @debug << message })
  end
end
