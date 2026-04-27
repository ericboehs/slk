# frozen_string_literal: true

require 'test_helper'

class UnreadCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @output = test_output
    @workspace = mock_workspace('test')
    stub_default_apis
  end

  def stub_default_apis
    @mock_client.stub('client.counts', { 'ok' => true, 'channels' => [], 'ims' => [] })
    @mock_client.stub('subscriptions.thread.getView',
                      { 'ok' => true, 'threads' => [], 'total_unread_replies' => 0 })
    @mock_client.stub('users.prefs.get', { 'prefs' => { 'muted_channels' => '' } })
    @mock_client.stub('conversations.history',
                      { 'ok' => true,
                        'messages' => [{ 'ts' => '1.0', 'text' => 'hi', 'user' => 'U1' }] })
    @mock_client.stub('conversations.mark', { 'ok' => true })
    @mock_client.stub('conversations.list', { 'ok' => true, 'channels' => [] })
  end

  def runner
    @runner ||= build_runner
  end

  def build_runner
    cache_store = Slk::Services::CacheStore.new(paths: temp_paths)
    config = mock_config
    runner = Slk::Runner.new(output: @output, api_client: @mock_client,
                             cache_store: cache_store, config: config)
    workspace = @workspace
    runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    runner.define_singleton_method(:all_workspaces) { [workspace] }
    runner
  end

  def mock_config
    config = Object.new
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }
    config.define_singleton_method(:primary_workspace) { 'test' }
    config
  end

  def temp_paths
    @temp_paths ||= TempPaths.new
  end

  class TempPaths
    def initialize
      @dir = Dir.mktmpdir('slk-unread-test')
    end

    def cache_file(name) = File.join(@dir, name)
    def ensure_cache_dir = FileUtils.mkdir_p(@dir)
  end

  def io_string = @output.instance_variable_get(:@io).string
  def err_string = @output.instance_variable_get(:@err).string

  def execute_with_args(args)
    Slk::Commands::Unread.new(args, runner: runner).execute
  end

  def test_help
    assert_equal 0, execute_with_args(['--help'])
    assert_includes io_string, 'slk unread'
  end

  def test_show_no_unreads
    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'No unread messages'
  end

  def test_show_with_unread_channel
    stub_unread_channel
    assert_equal 0, execute_with_args([])
    assert_includes io_string, '#'
  end

  def test_show_with_unread_dm
    stub_unread_dm
    assert_equal 0, execute_with_args([])
    assert_includes io_string, '@'
  end

  def test_json_output
    stub_unread_channel
    assert_equal 0, execute_with_args(['--json'])
    parsed = JSON.parse(extract_json(io_string))
    assert parsed.key?('channels')
    assert parsed.key?('dms')
  end

  def test_json_output_with_dm
    stub_unread_dm
    assert_equal 0, execute_with_args(['--json'])
    parsed = JSON.parse(extract_json(io_string))
    assert_equal 1, parsed['dms'].length
  end

  def extract_json(str)
    str[str.index('{')..]
  end

  def test_limit_option
    cmd = Slk::Commands::Unread.new(['-n', '5'], runner: runner)
    assert_equal 5, cmd.options[:limit]
  end

  def test_long_limit_option
    cmd = Slk::Commands::Unread.new(['--limit', '15'], runner: runner)
    assert_equal 15, cmd.options[:limit]
  end

  def test_muted_option
    cmd = Slk::Commands::Unread.new(['--muted'], runner: runner)
    assert cmd.options[:muted]
  end

  def test_clear_all
    assert_equal 0, execute_with_args(['clear'])
  end

  def test_clear_specific_channel_by_id
    stub_unread_channel
    assert_equal 0, execute_with_args(%w[clear C1])
    assert_includes io_string, 'Marked'
  end

  def test_clear_specific_channel_by_name_via_cache
    cache_store = runner.cache_store
    cache_store.set_channel('test', 'general', 'C1')
    @mock_client.stub('conversations.history',
                      { 'ok' => true, 'messages' => [{ 'ts' => '1.0' }] })
    assert_equal 0, execute_with_args(%w[clear #general])
    assert_includes io_string, 'Marked'
  end

  def test_clear_specific_channel_via_api_lookup
    @mock_client.stub('conversations.list', {
                        'ok' => true,
                        'channels' => [{ 'id' => 'C2', 'name' => 'random' }]
                      })
    @mock_client.stub('conversations.history',
                      { 'ok' => true, 'messages' => [{ 'ts' => '1.0' }] })
    assert_equal 0, execute_with_args(%w[clear #random])
  end

  def test_clear_channel_not_found
    @mock_client.stub('conversations.list', { 'ok' => true, 'channels' => [] })
    assert_raises(Slk::ConfigError) { execute_with_args(%w[clear #nonexistent]) }
  end

  def test_unknown_action
    assert_equal 1, execute_with_args(['foo'])
    assert_includes err_string, 'Unknown action'
  end

  def test_api_error
    @mock_client.define_singleton_method(:post) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'auth_error'
    end
    assert_equal 1, execute_with_args([])
    assert_includes err_string, 'auth_error'
  end

  def test_show_with_reaction_timestamps
    stub_unread_channel
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })
    assert_equal 0, execute_with_args(['--reaction-timestamps'])
  end

  def test_unknown_option
    assert_equal 1, execute_with_args(['--bogus'])
    assert_includes err_string, 'Unknown option'
  end

  def test_show_with_muted_option
    stub_unread_channel
    assert_equal 0, execute_with_args(['--muted'])
  end

  def test_dm_with_user_name_in_cache_for_json
    runner.cache_store.set_user('test', 'U2', 'Ashley')
    runner.cache_store.set_channel('test', 'general', 'C1')
    @mock_client.stub('client.counts', {
                        'ok' => true,
                        'channels' => [{ 'id' => 'C1', 'has_unreads' => true, 'mention_count' => 0 }],
                        'ims' => [{ 'id' => 'D1', 'has_unreads' => true, 'mention_count' => 0,
                                    'user' => 'U2' }]
                      })
    assert_equal 0, execute_with_args(['--json'])
    parsed = JSON.parse(extract_json(io_string))
    assert_equal 'Ashley', parsed['dms'].first['user_name']
    assert_equal 'general', parsed['channels'].first['name']
  end

  def test_show_with_threads_api_not_ok
    @mock_client.stub('subscriptions.thread.getView', { 'ok' => false })
    assert_equal 0, execute_with_args([])
  end

  def test_clear_single_channel_no_messages_returns_no_marker
    @mock_client.stub('conversations.history', { 'ok' => true, 'messages' => [] })
    assert_equal 0, execute_with_args(%w[clear C1])
  end

  def test_dm_no_user_id_in_json
    @mock_client.stub('client.counts', {
                        'ok' => true, 'channels' => [],
                        'ims' => [{ 'id' => 'D1', 'has_unreads' => true, 'mention_count' => 0 }]
                      })
    @mock_client.stub('conversations.info', { 'ok' => true, 'channel' => {} })
    assert_equal 0, execute_with_args(['--json'])
  end

  def test_show_with_threads
    @mock_client.stub('subscriptions.thread.getView', {
                        'ok' => true, 'total_unread_replies' => 1,
                        'threads' => [{ 'unread_replies' => [{ 'ts' => '1.0', 'text' => 't', 'user' => 'U2' }],
                                        'root_msg' => { 'channel' => 'C1', 'thread_ts' => '1.0',
                                                        'user' => 'U1', 'text' => 'parent' } }]
                      })
    @mock_client.stub('conversations.info', {
                        'ok' => true, 'channel' => { 'name' => 'general', 'id' => 'C1' }
                      })
    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'Threads'
  end

  private

  def stub_unread_channel
    @mock_client.stub('client.counts', {
                        'ok' => true, 'ims' => [],
                        'channels' => [{ 'id' => 'C1', 'has_unreads' => true, 'mention_count' => 0,
                                         'latest' => '1.0' }]
                      })
  end

  def stub_unread_dm
    @mock_client.stub('client.counts', {
                        'ok' => true, 'channels' => [],
                        'ims' => [{ 'id' => 'D1', 'has_unreads' => true, 'mention_count' => 1,
                                    'user' => 'U2', 'latest' => '1.0' }]
                      })
    @mock_client.stub('conversations.info', {
                        'ok' => true, 'channel' => { 'user' => 'U2' }
                      })
    @mock_client.stub('users.info', {
                        'ok' => true, 'user' => { 'id' => 'U2', 'profile' => { 'real_name' => 'Friend' } }
                      })
  end
end
