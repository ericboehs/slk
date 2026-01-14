# frozen_string_literal: true

require 'test_helper'

class BaseCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def test_error_returns_exit_code_1
    command = create_test_command([])
    result = command.send(:error, 'Something went wrong')

    assert_equal 1, result
    assert_includes @err.string, 'Something went wrong'
  end

  def test_error_writes_to_stderr
    command = create_test_command([])
    command.send(:error, 'Test error message')

    assert_includes @err.string, 'Test error message'
    assert_empty @io.string # stdout should be empty
  end

  def test_validate_options_returns_nil_when_valid
    command = create_test_command([])
    result = command.send(:validate_options)

    assert_nil result
  end

  def test_validate_options_returns_exit_code_for_help
    command = create_test_command(['--help'])
    result = command.send(:validate_options)

    assert_equal 0, result
  end

  def test_validate_options_returns_exit_code_for_unknown_options
    command = create_test_command(['--invalid-option'])
    result = command.send(:validate_options)

    assert_equal 1, result
    assert_includes @err.string, 'Unknown option'
  end

  def test_check_unknown_options_calls_error_twice
    command = create_test_command(['--bad-flag'])
    result = command.send(:check_unknown_options)

    assert_equal 1, result
    # Both error messages should be present
    assert_includes @err.string, 'Unknown option'
    assert_includes @err.string, '--help'
  end

  private

  def create_test_command(args)
    token_store = Object.new
    workspace = mock_workspace('test')
    token_store.define_singleton_method(:workspace) { |_name| workspace }
    token_store.define_singleton_method(:all_workspaces) { [workspace] }
    token_store.define_singleton_method(:workspace_names) { ['test'] }
    token_store.define_singleton_method(:empty?) { false }
    token_store.define_singleton_method(:on_warning=) { |_| }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| }

    runner = SlackCli::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      preset_store: preset_store
    )

    # Create a simple concrete command that doesn't override handle_option
    TestCommand.new(args, runner: runner)
  end

  # Minimal concrete command for testing Base behavior
  class TestCommand < SlackCli::Commands::Base
    def execute
      result = validate_options
      return result if result

      0
    end

    def help_text
      'Test command help'
    end
  end
end
