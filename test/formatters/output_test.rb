# frozen_string_literal: true

require 'test_helper'

class OutputTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
  end

  def output(**)
    Slk::Formatters::Output.new(io: @io, err: @err, color: false, **)
  end

  def color_output(**)
    Slk::Formatters::Output.new(io: @io, err: @err, color: true, **)
  end

  def test_puts_writes_to_io
    output.puts('hello')
    assert_includes @io.string, 'hello'
  end

  def test_quiet_silences_puts_print_warn
    out = output(quiet: true)
    out.puts('a')
    out.print('b')
    out.warn('c')
    assert_equal '', @io.string
    refute_includes @err.string, 'c'
  end

  def test_error_writes_to_err
    output.error('boom')
    assert_includes @err.string, 'Error'
    assert_includes @err.string, 'boom'
  end

  def test_warn_writes_to_err
    output.warn('careful')
    assert_includes @err.string, 'Warning'
  end

  def test_success_writes_to_io
    output.success('done')
    assert_includes @io.string, 'done'
  end

  def test_info_writes_to_io
    output.info('an info')
    assert_includes @io.string, 'an info'
  end

  def test_debug_only_when_verbose
    output.debug('hidden')
    refute_includes @err.string, 'hidden'

    out = output(verbose: true)
    out.debug('shown')
    assert_includes @err.string, 'shown'
  end

  def test_color_helpers_wrap_when_color_enabled
    out = color_output
    assert_includes out.red('a'), "\e[0;31m"
    assert_includes out.green('a'), "\e[0;32m"
    assert_includes out.yellow('a'), "\e[0;33m"
    assert_includes out.blue('a'), "\e[0;34m"
    assert_includes out.magenta('a'), "\e[0;35m"
    assert_includes out.cyan('a'), "\e[0;36m"
    assert_includes out.gray('a'), "\e[0;90m"
    assert_includes out.bold('a'), "\e[1m"
  end

  def test_color_helpers_pass_through_when_color_disabled
    assert_equal 'hello', output.red('hello')
    assert_equal 'hello', output.green('hello')
  end

  def test_color_default_uses_tty
    tty_io = StringIO.new
    tty_io.define_singleton_method(:tty?) { true }
    out = Slk::Formatters::Output.new(io: tty_io, err: @err)
    assert out.color?
  end

  def test_with_verbose_creates_new_instance
    out = output
    refute out.verbose
    new_out = out.with_verbose(true)
    refute_same out, new_out
    assert new_out.verbose
  end

  def test_with_quiet_creates_new_instance
    out = output
    refute out.quiet
    new_out = out.with_quiet(true)
    assert new_out.quiet
  end

  def test_color_falsy_when_explicit_false
    out = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    refute out.color?
  end
end
