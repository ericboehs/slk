# frozen_string_literal: true

require 'test_helper'

class ThreadCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @mock_client = MockApiClient.new
  end

  def test_missing_target_shows_error
    command = build_command([])

    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Usage: slk thread'
  end

  def test_non_url_target_shows_error
    command = build_command(['#general'])

    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'thread command requires a Slack message URL'
  end

  def test_channel_only_url_shows_error
    command = build_command(['https://test.slack.com/archives/C123'])

    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'thread command requires a Slack message URL'
  end

  def test_fetches_thread_via_replies_api
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    result = command.execute

    assert_equal 0, result

    # Verify it called conversations.replies, not conversations.history
    methods_called = @mock_client.calls.map { |c| c[:method] }
    assert_includes methods_called, 'conversations.replies'
    refute_includes methods_called, 'conversations.history'
  end

  def test_displays_parent_and_all_replies
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Parent message'
    assert_includes @io.string, 'First reply'
    assert_includes @io.string, 'Second reply'
  end

  def test_messages_display_in_chronological_order
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    command.execute

    parent_pos = @io.string.index('Parent message')
    first_pos = @io.string.index('First reply')
    second_pos = @io.string.index('Second reply')
    assert parent_pos < first_pos, 'Parent should appear before First reply'
    assert first_pos < second_pos, 'First reply should appear before Second reply'
  end

  def test_works_with_thread_ts_url
    @mock_client.stub('conversations.replies', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1234.0001', 'user' => 'U123', 'text' => 'Parent',
                            'thread_ts' => '1234.0001' },
                          { 'ts' => '1234.0002', 'user' => 'U456', 'text' => 'Reply',
                            'thread_ts' => '1234.0001' }
                        ]
                      })

    command = build_command(['https://test.slack.com/archives/C123/p1234000002000000?thread_ts=1234.0001'])
    stub_target_resolver(command, msg_ts: '1234000002.000000', thread_ts: '1234.0001')

    result = command.execute

    assert_equal 0, result
    # Should use thread_ts (1234.0001) as the ts param for replies API
    replies_call = @mock_client.calls.find { |c| c[:method] == 'conversations.replies' }
    assert replies_call, 'Expected conversations.replies to be called'
    assert_equal '1234.0001', replies_call[:params][:ts]
  end

  def test_json_output
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000', '--json'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    result = command.execute

    assert_equal 0, result
    output = JSON.parse(@io.string)
    assert_instance_of Array, output
    assert_equal 3, output.length
    assert_equal 'Parent message', output[0]['text']
    assert_equal 'First reply', output[1]['text']
    assert_equal 'Second reply', output[2]['text']
  end

  def test_help_text_renders
    command = build_command(['--help'])

    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk thread <url>'
    assert_includes @io.string, 'View a message thread'
  end

  def test_no_emoji_option_passes_through
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000', '--no-emoji'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    result = command.execute

    assert_equal 0, result
    options = command.instance_variable_get(:@options)
    assert options[:no_emoji]
  end

  def test_no_reactions_option_passes_through
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000', '--no-reactions'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    result = command.execute

    assert_equal 0, result
    options = command.instance_variable_get(:@options)
    assert options[:no_reactions]
  end

  def test_no_names_option_passes_through
    stub_replies_response

    command = build_command(['https://test.slack.com/archives/C123/p1234000001000000', '--no-names'])
    stub_target_resolver(command, msg_ts: '1234000001.000000')

    result = command.execute

    assert_equal 0, result
    options = command.instance_variable_get(:@options)
    assert options[:no_names]
  end

  private

  def stub_replies_response
    @mock_client.stub('conversations.replies', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1234.0001', 'user' => 'U123', 'text' => 'Parent message',
                            'thread_ts' => '1234.0001' },
                          { 'ts' => '1234.0002', 'user' => 'U456', 'text' => 'First reply',
                            'thread_ts' => '1234.0001' },
                          { 'ts' => '1234.0003', 'user' => 'U789', 'text' => 'Second reply',
                            'thread_ts' => '1234.0001' }
                        ]
                      })
  end

  def stub_target_resolver(command, msg_ts: nil, thread_ts: nil)
    command.define_singleton_method(:target_resolver) do
      resolver = Object.new
      ws = Slk::Models::Workspace.new(name: 'test', token: 'xoxb-test')
      result = Slk::Services::TargetResolver::Result.new(
        workspace: ws, channel_id: 'C123', thread_ts: thread_ts, msg_ts: msg_ts
      )
      resolver.define_singleton_method(:resolve) { |_target, **_opts| result }
      resolver
    end
  end

  def build_command(args)
    runner = build_runner
    Slk::Commands::Thread.new(args, runner: runner)
  end

  def build_runner
    token_store = Object.new
    workspace_list = [mock_workspace('test')]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end
    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store
    )
  end
end
