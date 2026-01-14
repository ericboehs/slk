# frozen_string_literal: true

require 'test_helper'

class DndCommandTest < Minitest::Test
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
    token_store.define_singleton_method(:on_warning=) { |_| }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { workspace_list.first&.name }
    config.define_singleton_method(:on_warning=) { |_| }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| }

    SlackCli::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store,
      cache_store: cache_store
    )
  end

  def test_get_status_shows_dnd_off
    @mock_client.stub('dnd.info', {
      'ok' => true,
      'snooze_enabled' => false,
      'dnd_enabled' => false
    })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'DND:'
    assert_includes @io.string, 'off'
  end

  def test_get_status_shows_snoozing
    @mock_client.stub('dnd.info', {
      'ok' => true,
      'snooze_enabled' => true,
      'snooze_remaining' => 1800,
      'dnd_enabled' => false
    })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['status'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'snoozing'
  end

  def test_set_snooze_with_duration
    @mock_client.stub('dnd.setSnooze', { 'ok' => true, 'snooze_enabled' => true })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['1h'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'dnd.setSnooze' }
    assert call
    assert_equal 60, call[:params][:num_minutes]
  end

  def test_set_snooze_on_default_duration
    @mock_client.stub('dnd.setSnooze', { 'ok' => true, 'snooze_enabled' => true })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['on'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'dnd.setSnooze' }
    assert call
    assert_equal 60, call[:params][:num_minutes] # Default 1h
  end

  def test_set_snooze_on_with_duration
    @mock_client.stub('dnd.setSnooze', { 'ok' => true, 'snooze_enabled' => true })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['on', '30m'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'dnd.setSnooze' }
    assert call
    assert_equal 30, call[:params][:num_minutes]
  end

  def test_end_snooze
    @mock_client.stub('dnd.endSnooze', { 'ok' => true })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['off'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'dnd.endSnooze' }
    assert call
  end

  def test_end_alias
    @mock_client.stub('dnd.endSnooze', { 'ok' => true })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['end'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'dnd.endSnooze' }
    assert call
  end

  def test_snooze_alias
    @mock_client.stub('dnd.setSnooze', { 'ok' => true, 'snooze_enabled' => true })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['snooze', '2h'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'dnd.setSnooze' }
    assert call
    assert_equal 120, call[:params][:num_minutes]
  end

  def test_invalid_action_returns_error
    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['invalid'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown action'
  end

  def test_invalid_duration_returns_error
    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['on', 'badformat'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Invalid duration'
  end

  def test_help_option
    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk dnd'
    assert_includes @io.string, 'DURATION'
  end

  def test_api_error_returns_1
    api_client = Object.new
    api_client.define_singleton_method(:get) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, 'invalid_auth'
    end
    api_client.define_singleton_method(:post) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, 'invalid_auth'
    end

    runner = create_runner
    runner.instance_variable_set(:@api_client, api_client)

    command = SlackCli::Commands::Dnd.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Failed'
  end

  def test_info_alias_for_status
    @mock_client.stub('dnd.info', {
      'ok' => true,
      'snooze_enabled' => false,
      'dnd_enabled' => false
    })

    runner = create_runner
    command = SlackCli::Commands::Dnd.new(['info'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'DND:'
  end
end
