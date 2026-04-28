# frozen_string_literal: true

require 'test_helper'

class BaseCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def test_error_returns_exit_code_one
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

  def test_default_execute_raises_not_implemented
    cmd = Slk::Commands::Base.new([], runner: build_runner)
    assert_raises(NotImplementedError) { cmd.execute }
  end

  def test_workspace_option_short_flag
    cmd = create_test_command(['-w', 'foo'])
    assert_equal 'foo', cmd.options[:workspace]
  end

  def test_width_option_zero_disables_wrapping
    cmd = create_test_command(['--width', '0'])
    assert_nil cmd.options[:width]
  end

  def test_width_option_with_number
    cmd = create_test_command(['--width', '100'])
    assert_equal 100, cmd.options[:width]
  end

  def test_no_wrap_disables_wrapping
    cmd = create_test_command(['--no-wrap'])
    assert_nil cmd.options[:width]
  end

  def test_quiet_short_and_long
    cmd = create_test_command(['-q'])
    assert cmd.options[:quiet]
    cmd2 = create_test_command(['--quiet'])
    assert cmd2.options[:quiet]
  end

  def test_verbose_levels
    short = create_test_command(['-v'])
    assert short.options[:verbose]
    refute short.options[:very_verbose]
    very = create_test_command(['-vv'])
    assert very.options[:very_verbose]
  end

  def test_json_and_markdown_flags
    cmd = create_test_command(['--json', '--markdown'])
    assert cmd.options[:json]
    assert cmd.options[:markdown]
  end

  def test_format_specific_flags
    cmd = create_test_command(['--no-emoji', '--no-reactions', '--no-names',
                               '--reaction-names', '--reaction-timestamps',
                               '--fetch-attachments', '--all'])
    assert cmd.options[:no_emoji]
    assert cmd.options[:no_reactions]
    assert cmd.options[:no_names]
    assert cmd.options[:reaction_names]
    assert cmd.options[:reaction_timestamps]
    assert cmd.options[:fetch_attachments]
    assert cmd.options[:all]
  end

  def test_target_workspaces_with_all
    cmd = create_test_command(['--all'])
    assert_equal 1, cmd.send(:target_workspaces).size
  end

  def test_target_workspaces_with_specific_workspace
    cmd = create_test_command(['-w', 'test'])
    assert_equal 1, cmd.send(:target_workspaces).size
  end

  def test_target_workspaces_default
    cmd = create_test_command([])
    assert_equal 1, cmd.send(:target_workspaces).size
  end

  def test_format_options_returns_hash
    cmd = create_test_command([])
    opts = cmd.send(:format_options)
    assert_kind_of Hash, opts
    assert_includes opts.keys, :no_emoji
    assert_includes opts.keys, :width
  end

  def test_quiet_silences_success_info_puts_print
    cmd = create_test_command(['-q'])
    cmd.send(:success, 'a')
    cmd.send(:info, 'b')
    cmd.send(:puts, 'c')
    cmd.send(:print, 'd')
    assert_empty @io.string
  end

  def test_debug_only_when_verbose
    silent = create_test_command([])
    silent.send(:debug, 'hidden')
    refute_includes @err.string, 'hidden'
  end

  def test_warn_writes_to_err
    cmd = create_test_command([])
    cmd.send(:warn, 'careful')
    assert_includes @err.string, 'Warning'
  end

  def test_output_json_pretty_generates
    cmd = create_test_command([])
    cmd.send(:output_json, { 'a' => 1 })
    assert_match(/"a": 1/, @io.string)
  end

  def test_default_width_when_tty
    cmd = create_test_command([])
    $stdout.stub(:tty?, true) do
      assert_equal 72, cmd.send(:default_width)
    end
  end

  def test_default_width_when_not_tty
    cmd = create_test_command([])
    $stdout.stub(:tty?, false) do
      assert_nil cmd.send(:default_width)
    end
  end

  def test_unknown_options_predicate_returns_falsy_when_none
    cmd = create_test_command([])
    refute cmd.send(:unknown_options?)
  end

  def test_check_unknown_options_returns_nil_when_empty
    cmd = create_test_command([])
    cmd.instance_variable_set(:@unknown_options, [])
    assert_nil cmd.send(:check_unknown_options)
  end

  def test_unknown_options_predicate_returns_true_when_present
    cmd = create_test_command(['--bogus'])
    assert cmd.send(:unknown_options?)
  end

  def build_runner
    create_test_command([]).runner
  end

  private

  def create_test_command(args)
    token_store = Object.new
    workspace = mock_workspace('test')
    token_store.define_singleton_method(:workspace) { |_name| workspace }
    token_store.define_singleton_method(:all_workspaces) { [workspace] }
    token_store.define_singleton_method(:workspace_names) { ['test'] }
    token_store.define_singleton_method(:empty?) { false }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    runner = Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      preset_store: preset_store
    )

    # Create a simple concrete command that doesn't override handle_option
    TestCommand.new(args, runner: runner)
  end

  # Minimal concrete command for testing Base behavior
  class TestCommand < Slk::Commands::Base
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
