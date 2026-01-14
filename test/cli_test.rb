# frozen_string_literal: true

require 'test_helper'

class CLITest < Minitest::Test
  def setup
    @output = MockOutput.new
  end

  def test_version_flag
    cli = SlackCli::CLI.new(['--version'], output: @output)
    result = cli.run

    assert_equal 0, result
    assert_match(/slk v\d+\.\d+\.\d+/, @output.stdout)
  end

  def test_version_short_flag
    cli = SlackCli::CLI.new(['-V'], output: @output)
    result = cli.run

    assert_equal 0, result
    assert_match(/slk v/, @output.stdout)
  end

  def test_version_command
    cli = SlackCli::CLI.new(['version'], output: @output)
    result = cli.run

    assert_equal 0, result
    assert_match(/slk v/, @output.stdout)
  end

  def test_help_with_no_arguments
    cli = SlackCli::CLI.new([], output: @output)
    result = cli.run

    assert_equal 0, result
  end

  def test_help_flag
    cli = SlackCli::CLI.new(['--help'], output: @output)
    result = cli.run

    assert_equal 0, result
  end

  def test_help_short_flag
    cli = SlackCli::CLI.new(['-h'], output: @output)
    result = cli.run

    assert_equal 0, result
  end

  def test_unknown_command
    cli = SlackCli::CLI.new(['nonexistent'], output: @output)
    result = cli.run

    assert_equal 1, result
    assert_match(/unknown command/i, @output.stderr)
  end

  def test_command_routing_to_help
    # Help is a command that doesn't require workspace setup
    cli = SlackCli::CLI.new(['help'], output: @output)
    result = cli.run

    assert_equal 0, result
  end

  def test_commands_hash_contains_expected_commands
    expected = %w[status presence dnd messages thread unread catchup preset workspaces cache emoji config help]

    expected.each do |cmd|
      assert SlackCli::CLI::COMMANDS.key?(cmd), "Missing command: #{cmd}"
    end
  end

  def test_commands_hash_is_frozen
    assert SlackCli::CLI::COMMANDS.frozen?
  end

  def test_config_error_handling
    cli = SlackCli::CLI.new(['help'], output: @output)

    # Stub the run_command method to raise ConfigError
    cli.define_singleton_method(:run_command) do |_name, _args|
      raise SlackCli::ConfigError, "Test config error"
    end

    result = cli.run

    assert_equal 1, result
    assert_includes @output.stderr, "Test config error"
  end

  def test_encryption_error_handling
    cli = SlackCli::CLI.new(['help'], output: @output)

    cli.define_singleton_method(:run_command) do |_name, _args|
      raise SlackCli::EncryptionError, "Test encryption error"
    end

    result = cli.run

    assert_equal 1, result
    assert_includes @output.stderr, "Encryption error"
    assert_includes @output.stderr, "Test encryption error"
  end

  def test_api_error_handling
    cli = SlackCli::CLI.new(['help'], output: @output)

    cli.define_singleton_method(:run_command) do |_name, _args|
      raise SlackCli::ApiError, "rate_limited"
    end

    result = cli.run

    assert_equal 1, result
    assert_includes @output.stderr, "API error"
    assert_includes @output.stderr, "rate_limited"
  end

  def test_interrupt_handling
    cli = SlackCli::CLI.new(['help'], output: @output)

    cli.define_singleton_method(:run_command) do |_name, _args|
      raise Interrupt
    end

    result = cli.run

    assert_equal 130, result
    assert_includes @output.stdout, "Interrupted"
  end

  def test_standard_error_handling
    cli = SlackCli::CLI.new(['help'], output: @output)

    cli.define_singleton_method(:run_command) do |_name, _args|
      raise StandardError, "Something unexpected"
    end

    result = cli.run

    assert_equal 1, result
    assert_includes @output.stderr, "Unexpected error"
    assert_includes @output.stderr, "Something unexpected"
  end

  # Mock output class for testing
  class MockOutput
    attr_reader :stdout, :stderr

    def initialize
      @stdout = ''
      @stderr = ''
    end

    def puts(msg = '')
      @stdout += "#{msg}\n"
    end

    def print(msg)
      @stdout += msg
    end

    def error(msg)
      @stderr += "Error: #{msg}\n"
    end

    def warn(msg)
      @stderr += "Warning: #{msg}\n"
    end

    def debug(msg)
      # Ignore debug output
    end

    def verbose?
      false
    end
  end
end
