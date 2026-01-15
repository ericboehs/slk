# frozen_string_literal: true

require 'test_helper'

class PresenceCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def create_runner(workspaces: nil)
    token_store = Object.new
    workspace_list = workspaces || [mock_workspace('test')]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end
    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { workspace_list.first&.name }
    config.define_singleton_method(:on_warning=) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }

    SlackCli::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store,
      cache_store: cache_store
    )
  end

  def test_get_presence_shows_status
    @mock_client.stub('users.getPresence', {
                        'ok' => true,
                        'presence' => 'active',
                        'manual_away' => false
                      })

    runner = create_runner
    command = SlackCli::Commands::Presence.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Presence:'
    assert_includes @io.string, 'active'
  end

  def test_get_presence_shows_away
    @mock_client.stub('users.getPresence', {
                        'ok' => true,
                        'presence' => 'away',
                        'manual_away' => true
                      })

    runner = create_runner
    command = SlackCli::Commands::Presence.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'away'
  end

  def test_set_presence_away
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    command = SlackCli::Commands::Presence.new(['away'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert call
    assert_equal 'away', call[:params][:presence]
  end

  def test_set_presence_auto
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    command = SlackCli::Commands::Presence.new(['auto'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert call
    assert_equal 'auto', call[:params][:presence]
  end

  def test_set_presence_active_alias
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    command = SlackCli::Commands::Presence.new(['active'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert call
    assert_equal 'auto', call[:params][:presence]
  end

  def test_invalid_presence_returns_error
    runner = create_runner
    command = SlackCli::Commands::Presence.new(['invalid'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown presence'
  end

  def test_help_option
    runner = create_runner
    command = SlackCli::Commands::Presence.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk presence'
    assert_includes @io.string, 'away'
    assert_includes @io.string, 'auto'
  end

  def test_api_error_returns_one
    api_client = Object.new
    api_client.define_singleton_method(:get) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, 'user_not_found'
    end
    api_client.define_singleton_method(:post) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, 'user_not_found'
    end

    runner = create_runner
    runner.instance_variable_set(:@api_client, api_client)

    command = SlackCli::Commands::Presence.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Failed'
  end

  def test_shows_multiple_workspaces
    workspaces = [
      mock_workspace('workspace1'),
      mock_workspace('workspace2')
    ]

    @mock_client.stub('users.getPresence', {
                        'ok' => true,
                        'presence' => 'active',
                        'manual_away' => false
                      })

    runner = create_runner(workspaces: workspaces)
    command = SlackCli::Commands::Presence.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'workspace1'
    assert_includes @io.string, 'workspace2'
  end

  def test_unknown_option_returns_error
    runner = create_runner
    command = SlackCli::Commands::Presence.new(['--invalid-option'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown option'
    assert_includes @err.string, '--invalid-option'
  end

  def test_unknown_short_option_returns_error
    runner = create_runner
    command = SlackCli::Commands::Presence.new(['-z'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown option'
    assert_includes @err.string, '-z'
  end
end
