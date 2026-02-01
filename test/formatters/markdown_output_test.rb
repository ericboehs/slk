# frozen_string_literal: true

require 'test_helper'

class MarkdownOutputTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err)
  end

  def test_puts_writes_to_io
    @output.puts('Hello world')
    assert_equal "Hello world\n", @io.string
  end

  def test_puts_empty_line
    @output.puts
    assert_equal "\n", @io.string
  end

  def test_print_writes_without_newline
    @output.print('Hello')
    assert_equal 'Hello', @io.string
  end

  def test_bold_wraps_in_double_asterisks
    result = @output.bold('text')
    assert_equal '**text**', result
  end

  def test_red_wraps_in_double_asterisks
    result = @output.red('error')
    assert_equal '**error**', result
  end

  def test_green_returns_plain_text
    result = @output.green('success')
    assert_equal 'success', result
  end

  def test_yellow_wraps_in_single_asterisks
    result = @output.yellow('warning')
    assert_equal '*warning*', result
  end

  def test_blue_wraps_in_backticks
    result = @output.blue('timestamp')
    assert_equal '`timestamp`', result
  end

  def test_magenta_wraps_in_single_asterisks
    result = @output.magenta('highlight')
    assert_equal '*highlight*', result
  end

  def test_cyan_wraps_in_backticks
    result = @output.cyan('code')
    assert_equal '`code`', result
  end

  def test_gray_wraps_in_single_asterisks
    result = @output.gray('secondary')
    assert_equal '*secondary*', result
  end

  def test_error_writes_to_stderr
    @output.error('Something went wrong')
    assert_equal "**Error:** Something went wrong\n", @err.string
  end

  def test_warn_writes_to_stderr
    @output.warn('Be careful')
    assert_equal "*Warning:* Be careful\n", @err.string
  end

  def test_success_includes_checkmark
    @output.success('Done')
    assert_equal "✓ Done\n", @io.string
  end

  def test_info_writes_plain_text
    @output.info('Information')
    assert_equal "Information\n", @io.string
  end

  def test_debug_only_shows_when_verbose
    @output.debug('Debug message')
    assert_empty @err.string

    verbose_output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, verbose: true)
    verbose_output.debug('Debug message')
    assert_equal "*[debug]* Debug message\n", @err.string
  end

  def test_quiet_mode_suppresses_output
    quiet_output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, quiet: true)
    quiet_output.puts('Should not appear')
    quiet_output.print('Also hidden')
    quiet_output.info('Info hidden')
    quiet_output.success('Success hidden')

    assert_empty @io.string
  end

  def test_quiet_mode_still_shows_errors
    quiet_output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, quiet: true)
    quiet_output.error('Error shown')

    assert_equal "**Error:** Error shown\n", @err.string
  end

  def test_quiet_mode_suppresses_warn
    quiet_output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, quiet: true)
    quiet_output.warn('Warning hidden')

    assert_empty @err.string
  end

  def test_accepts_color_parameter_for_interface_compatibility
    # Should not raise ArgumentError
    output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, color: true)
    assert_instance_of Slk::Formatters::MarkdownOutput, output
  end

  def test_formatting_methods_handle_nil_input
    assert_equal '****', @output.bold(nil)
    assert_equal '****', @output.red(nil)
    assert_equal '', @output.green(nil)
    assert_equal '**', @output.yellow(nil)
    assert_equal '``', @output.blue(nil)
    assert_equal '**', @output.magenta(nil)
    assert_equal '``', @output.cyan(nil)
    assert_equal '**', @output.gray(nil)
  end

  def test_formatting_methods_handle_numeric_input
    assert_equal '**123**', @output.bold(123)
    assert_equal '`456`', @output.cyan(456)
    assert_equal '789', @output.green(789)
  end

  def test_with_verbose_returns_new_instance
    new_output = @output.with_verbose(true)

    refute_same @output, new_output
    assert new_output.verbose
    refute @output.verbose
  end

  def test_with_quiet_returns_new_instance
    new_output = @output.with_quiet(true)

    refute_same @output, new_output
    assert new_output.quiet
    refute @output.quiet
  end

  def test_verbose_accessor
    refute @output.verbose

    verbose_output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, verbose: true)
    assert verbose_output.verbose
  end

  def test_quiet_accessor
    refute @output.quiet

    quiet_output = Slk::Formatters::MarkdownOutput.new(io: @io, err: @err, quiet: true)
    assert quiet_output.quiet
  end
end
