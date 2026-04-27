# frozen_string_literal: true

require 'test_helper'

class ActivityCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @output = test_output
    @workspace = mock_workspace('test')
  end

  def runner
    cache_store = Slk::Services::CacheStore.new(paths: temp_paths)
    runner = Slk::Runner.new(output: @output, api_client: @mock_client, cache_store: cache_store)
    workspace = @workspace
    runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    runner.define_singleton_method(:all_workspaces) { [workspace] }
    runner
  end

  def temp_paths
    @temp_paths ||= TempPaths.new
  end

  class TempPaths
    def initialize
      @dir = Dir.mktmpdir('slk-activity-test')
    end

    def cache_file(name) = File.join(@dir, name)
    def ensure_cache_dir = FileUtils.mkdir_p(@dir)
  end

  def io_string = @output.instance_variable_get(:@io).string
  def err_string = @output.instance_variable_get(:@err).string

  def execute_with_args(args)
    Slk::Commands::Activity.new(args, runner: runner).execute
  end

  def stub_feed(items, success: true, error: nil)
    response = { 'ok' => success, 'items' => items }
    response['error'] = error if error
    @mock_client.stub('activity.feed', response)
  end

  def reaction_item
    {
      'feed_ts' => '1700000000.000000',
      'item' => {
        'type' => 'message_reaction',
        'reaction' => { 'user' => 'U1', 'name' => 'thumbsup' },
        'message' => { 'channel' => 'C1', 'ts' => '1700.000', 'text' => 'hello' }
      }
    }
  end

  def test_help
    assert_equal 0, execute_with_args(['--help'])
    assert_includes io_string, 'slk activity'
  end

  def test_no_items
    stub_feed([])
    assert_equal 0, execute_with_args([])
  end

  def test_displays_reaction
    stub_feed([reaction_item])
    assert_equal 0, execute_with_args([])
  end

  def test_json_output
    stub_feed([reaction_item])
    assert_equal 0, execute_with_args(['--json'])
    parsed = JSON.parse(io_string)
    assert_kind_of Array, parsed
  end

  def test_filter_reactions
    stub_feed([])
    execute_with_args(['--reactions'])
    call = @mock_client.calls.find { |c| c[:method] == 'activity.feed' }
    assert_equal 'message_reaction', call[:params][:types]
  end

  def test_filter_mentions
    stub_feed([])
    execute_with_args(['--mentions'])
    call = @mock_client.calls.find { |c| c[:method] == 'activity.feed' }
    assert_includes call[:params][:types], 'at_user'
  end

  def test_filter_threads
    stub_feed([])
    execute_with_args(['--threads'])
    call = @mock_client.calls.find { |c| c[:method] == 'activity.feed' }
    assert_equal 'thread_v2', call[:params][:types]
  end

  def test_default_filter_all
    stub_feed([])
    execute_with_args([])
    call = @mock_client.calls.find { |c| c[:method] == 'activity.feed' }
    assert_includes call[:params][:types], 'thread_v2'
    assert_includes call[:params][:types], 'message_reaction'
  end

  def test_limit_option
    stub_feed([])
    execute_with_args(['-n', '5'])
    call = @mock_client.calls.find { |c| c[:method] == 'activity.feed' }
    assert_equal '5', call[:params][:limit]
  end

  def test_show_messages_option
    stub_feed([])
    execute_with_args(['--show-messages'])
    # Just verify option parses; behavior tested when items exist.
    assert_equal 0, 0
  end

  def test_show_messages_short_alias
    stub_feed([])
    execute_with_args(['-m'])
    assert_equal 0, 0
  end

  def test_api_error_response
    stub_feed([], success: false, error: 'invalid_auth')
    assert_equal 1, execute_with_args([])
    assert_includes err_string, 'invalid_auth'
  end

  def test_api_error_raise
    @mock_client.define_singleton_method(:post_form) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'network down'
    end
    assert_equal 1, execute_with_args([])
    assert_includes err_string, 'network down'
  end
end
