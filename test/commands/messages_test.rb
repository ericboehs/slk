# frozen_string_literal: true

require 'test_helper'

class MessagesCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @cache = MockCache.new
  end

  def test_missing_target_shows_error
    command = build_command([])

    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Usage: slk messages'
  end

  def test_fetch_channel_history
    @mock_client.stub('conversations.history', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1234.0001', 'user' => 'U123', 'text' => 'Hello' },
                          { 'ts' => '1234.0002', 'user' => 'U456', 'text' => 'World' }
                        ]
                      })

    command = build_command(['#general'])

    # Mock the target resolver
    command.define_singleton_method(:target_resolver) do
      resolver = Object.new
      ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-test')
      result = SlackCli::Services::TargetResolver::Result.new(
        workspace: ws, channel_id: 'C123', thread_ts: nil, msg_ts: nil
      )
      resolver.define_singleton_method(:resolve) { |_target, **_opts| result }
      resolver
    end

    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Hello'
    assert_includes @io.string, 'World'
  end

  def test_apply_default_limit_for_channel
    command = build_command(['#general'])

    # Access private method via send
    command.send(:apply_default_limit, nil)

    assert_equal 500, command.instance_variable_get(:@options)[:limit]
  end

  def test_apply_default_limit_for_message_url
    command = build_command(['#general'])

    command.send(:apply_default_limit, '1234567890.123456')

    assert_equal 50, command.instance_variable_get(:@options)[:limit]
  end

  def test_apply_thread_limit_keeps_parent_and_last_replies
    command = build_command(['#general', '-n', '3'])
    messages = [
      { 'ts' => '1.0', 'text' => 'parent' },
      { 'ts' => '1.1', 'text' => 'reply1' },
      { 'ts' => '1.2', 'text' => 'reply2' },
      { 'ts' => '1.3', 'text' => 'reply3' },
      { 'ts' => '1.4', 'text' => 'reply4' }
    ]

    result = command.send(:apply_thread_limit, messages)

    assert_equal 3, result.length
    assert_equal 'parent', result[0]['text']
    assert_equal 'reply3', result[1]['text']
    assert_equal 'reply4', result[2]['text']
  end

  def test_deduplicate_and_sort_removes_duplicates
    command = build_command(['#general'])
    messages = [
      { 'ts' => '1.2', 'text' => 'second' },
      { 'ts' => '1.1', 'text' => 'first' },
      { 'ts' => '1.2', 'text' => 'duplicate' },
      { 'ts' => '1.3', 'text' => 'third' }
    ]

    result = command.send(:deduplicate_and_sort, messages)

    assert_equal 3, result.length
    assert_equal(%w[1.1 1.2 1.3], result.map { |m| m['ts'] })
  end

  def test_adjust_timestamp_decrements_slightly
    command = build_command(['#general'])

    result = command.send(:adjust_timestamp, '1234567890.123456', -0.000001)

    assert_equal '1234567890.123455', result
  end

  def test_json_output_option
    @mock_client.stub('conversations.history', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1234.0001', 'user' => 'U123', 'text' => 'Hello' }
                        ]
                      })

    command = build_command(['#general', '--json'])

    command.define_singleton_method(:target_resolver) do
      resolver = Object.new
      ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-test')
      result = SlackCli::Services::TargetResolver::Result.new(
        workspace: ws, channel_id: 'C123', thread_ts: nil, msg_ts: nil
      )
      resolver.define_singleton_method(:resolve) { |_target, **_opts| result }
      resolver
    end

    result = command.execute

    assert_equal 0, result
    output = JSON.parse(@io.string)
    assert_instance_of Array, output
    assert_equal 'Hello', output.first['text']
  end

  private

  def build_command(args)
    runner = build_runner
    SlackCli::Commands::Messages.new(args, runner: runner)
  end

  def build_runner
    # Create a mock token store
    token_store = Object.new
    workspace_list = [mock_workspace('test')]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end
    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    # Create a mock config
    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }

    # Create a mock preset store
    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    SlackCli::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store
    )
  end

  # Simple mock cache for testing
  class MockCache
    def initialize
      @users = {}
      @channels = {}
      @channel_ids = {}
    end

    def get_user(workspace, user_id)
      @users["#{workspace}:#{user_id}"]
    end

    def set_user(workspace, user_id, name, persist: false) # rubocop:disable Lint/UnusedMethodArgument
      @users["#{workspace}:#{user_id}"] = name
    end

    def get_channel_name(workspace, channel_id)
      @channel_ids["#{workspace}:#{channel_id}"]
    end

    def get_channel_id(workspace, name)
      @channels["#{workspace}:#{name}"]
    end

    def set_channel(workspace, name, channel_id)
      @channels["#{workspace}:#{name}"] = channel_id
      @channel_ids["#{workspace}:#{channel_id}"] = name
    end

    def get_subteam(_workspace, _subteam_id)
      nil
    end
  end
end
