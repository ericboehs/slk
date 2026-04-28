# frozen_string_literal: true

require 'test_helper'

class CatchupCommandTest < Minitest::Test
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
    @mock_client.stub('subscriptions.thread.mark', { 'ok' => true })
    @mock_client.stub('auth.test', { 'ok' => true, 'user_id' => 'U1', 'team_id' => 'T1' })
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
      @dir = Dir.mktmpdir('slk-catchup-test')
    end

    def cache_file(name) = File.join(@dir, name)
    def ensure_cache_dir = FileUtils.mkdir_p(@dir)
  end

  def io_string = @output.instance_variable_get(:@io).string
  def err_string = @output.instance_variable_get(:@err).string

  def execute_with_args(args)
    Slk::Commands::Catchup.new(args, runner: runner).execute
  end

  def test_help
    assert_equal 0, execute_with_args(['--help'])
    assert_includes io_string, 'slk catchup'
  end

  def test_batch_no_unreads
    assert_equal 0, execute_with_args(['--batch'])
    assert_includes io_string, 'Marked'
  end

  def test_batch_with_muted_option
    assert_equal 0, execute_with_args(['--batch', '--muted'])
    assert_includes io_string, 'Marked'
  end

  def test_interactive_no_unreads
    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'No unread messages'
  end

  def test_limit_option
    cmd = Slk::Commands::Catchup.new(['-n', '20'], runner: runner)
    assert_equal 20, cmd.options[:limit]
  end

  def test_long_limit_option
    cmd = Slk::Commands::Catchup.new(['--limit', '15'], runner: runner)
    assert_equal 15, cmd.options[:limit]
  end

  def test_api_error_handling
    @mock_client.define_singleton_method(:post) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'rate limited'
    end
    assert_equal 1, execute_with_args(['--batch'])
    assert_includes err_string, 'rate limited'
  end

  def test_interactive_with_unread_dm_skip
    stub_unread_dm
    fake_input = StringIO.new("s\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_interactive_with_unread_dm_quit
    stub_unread_dm
    fake_input = StringIO.new("q\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_interactive_with_unread_channel_mark_read
    stub_unread_channel
    fake_input = StringIO.new("r\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_interactive_invalid_then_skip
    stub_unread_channel
    fake_input = StringIO.new("x\ns\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_interactive_open_action
    stub_unread_channel
    @mock_client.stub('auth.test', { 'ok' => true, 'user_id' => 'U1', 'team_id' => 'T1' })
    fake_input = StringIO.new("o\ns\n")
    $stdin = fake_input
    Slk::Support::Platform.stub(:open_url, true) do
      assert_equal 0, execute_with_args([])
    end
  ensure
    $stdin = STDIN
  end

  def test_threads_display_skip
    stub_unread_threads
    fake_input = StringIO.new("s\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_threads_display_mark_read
    stub_unread_threads
    fake_input = StringIO.new("r\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'Marked'
  ensure
    $stdin = STDIN
  end

  def test_threads_display_open
    stub_unread_threads
    fake_input = StringIO.new("o\n")
    $stdin = fake_input
    Slk::Support::Platform.stub(:open_url, true) do
      assert_equal 0, execute_with_args([])
    end
  ensure
    $stdin = STDIN
  end

  def test_threads_display_invalid_then_skip
    stub_unread_threads
    fake_input = StringIO.new("z\ns\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_threads_quit
    stub_unread_threads
    fake_input = StringIO.new("q\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_threads_with_no_unread_replies_filtered
    @mock_client.stub('subscriptions.thread.getView', {
                        'ok' => true, 'total_unread_replies' => 1,
                        'threads' => [{
                          'unread_replies' => [],
                          'root_msg' => { 'channel' => 'C1', 'thread_ts' => '1.0',
                                          'user' => 'U1', 'text' => 'p' }
                        }]
                      })
    fake_input = StringIO.new("s\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def test_muted_option_includes_muted
    stub_unread_channel
    assert_equal 0, execute_with_args(['--muted'])
  end

  def test_reaction_timestamps_enriches
    stub_unread_channel
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })
    fake_input = StringIO.new("s\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args(['--reaction-timestamps'])
  ensure
    $stdin = STDIN
  end

  def test_unread_dm_no_latest_ts
    @mock_client.stub('client.counts', {
                        'ok' => true, 'channels' => [],
                        'ims' => [{ 'id' => 'D1', 'has_unreads' => true, 'mention_count' => 0,
                                    'last_read' => nil, 'latest' => nil }]
                      })
    @mock_client.stub('conversations.info', { 'ok' => true, 'channel' => { 'user' => 'U2' } })
    @mock_client.stub('users.info',
                      { 'ok' => true, 'user' => { 'id' => 'U2', 'profile' => { 'real_name' => 'X' } } })
    fake_input = StringIO.new("r\n")
    $stdin = fake_input
    assert_equal 0, execute_with_args([])
  ensure
    $stdin = STDIN
  end

  def stub_unread_threads
    @mock_client.stub('subscriptions.thread.getView', {
                        'ok' => true, 'total_unread_replies' => 1,
                        'threads' => [{
                          'unread_replies' => [{ 'ts' => '1.1', 'text' => 'reply', 'user' => 'U2' }],
                          'root_msg' => { 'channel' => 'C1', 'thread_ts' => '1.0',
                                          'user' => 'U1', 'text' => 'p' }
                        }]
                      })
    @mock_client.stub('conversations.info', {
                        'ok' => true, 'channel' => { 'name' => 'general', 'id' => 'C1' }
                      })
  end

  private

  def stub_unread_dm
    @mock_client.stub('client.counts', {
                        'ok' => true, 'channels' => [],
                        'ims' => [{ 'id' => 'D1', 'has_unreads' => true, 'mention_count' => 1,
                                    'last_read' => '0', 'latest' => '1.0' }]
                      })
    @mock_client.stub('conversations.info', {
                        'ok' => true, 'channel' => { 'user' => 'U2' }
                      })
    @mock_client.stub('users.info', {
                        'ok' => true, 'user' => { 'id' => 'U2', 'profile' => { 'real_name' => 'Friend' } }
                      })
  end

  def stub_unread_channel
    @mock_client.stub('client.counts', {
                        'ok' => true, 'ims' => [],
                        'channels' => [{ 'id' => 'C1', 'has_unreads' => true, 'mention_count' => 0,
                                         'last_read' => '0', 'latest' => '1.0' }]
                      })
  end
end
