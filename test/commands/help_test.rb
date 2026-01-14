# frozen_string_literal: true

require 'test_helper'

class HelpCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def create_runner
    config = Object.new
    config.define_singleton_method(:primary_workspace) { nil }
    config.define_singleton_method(:on_warning=) { |_| }

    token_store = Object.new
    token_store.define_singleton_method(:empty?) { true }
    token_store.define_singleton_method(:all_workspaces) { [] }
    token_store.define_singleton_method(:workspace_names) { [] }
    token_store.define_singleton_method(:on_warning=) { |_| }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| }

    SlackCli::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      preset_store: preset_store,
      cache_store: cache_store
    )
  end

  def test_general_help_shows_all_commands
    runner = create_runner
    command = SlackCli::Commands::Help.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk'
    assert_includes @io.string, 'status'
    assert_includes @io.string, 'presence'
    assert_includes @io.string, 'dnd'
    assert_includes @io.string, 'messages'
    assert_includes @io.string, 'preset'
    assert_includes @io.string, 'workspaces'
  end

  def test_general_help_shows_global_options
    runner = create_runner
    command = SlackCli::Commands::Help.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, '--workspace'
    assert_includes @io.string, '--all'
    assert_includes @io.string, '--verbose'
    assert_includes @io.string, '--help'
  end

  def test_general_help_shows_examples
    runner = create_runner
    command = SlackCli::Commands::Help.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'EXAMPLES'
    assert_includes @io.string, 'slk status'
    assert_includes @io.string, 'slk dnd 1h'
  end

  def test_command_specific_help_for_status
    runner = create_runner
    command = SlackCli::Commands::Help.new(['status'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk status'
  end

  def test_command_specific_help_for_presence
    runner = create_runner
    command = SlackCli::Commands::Help.new(['presence'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk presence'
  end

  def test_unknown_command_shows_error
    runner = create_runner
    command = SlackCli::Commands::Help.new(['nonexistent'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @err.string, 'Unknown command'
    assert_includes @io.string, 'Available commands'
  end

  def test_shows_version
    runner = create_runner
    command = SlackCli::Commands::Help.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'v'
  end
end
