# frozen_string_literal: true

require 'test_helper'

class InteractivePromptTest < Minitest::Test
  Prompt = Slk::Support::InteractivePrompt

  def teardown
    $stdin = STDIN
    $stdout = STDOUT
  end

  def test_read_single_char_uses_raw_when_tty
    fake_stdin = TtyStdin.new('y')
    $stdin = fake_stdin

    assert_equal 'y', Prompt.read_single_char
    assert fake_stdin.raw_called?
  end

  def test_read_single_char_reads_line_and_chomps_when_not_tty
    $stdin = StringIO.new("hello\n")

    assert_equal 'hello', Prompt.read_single_char
  end

  def test_read_single_char_returns_nil_when_stdin_empty_non_tty
    $stdin = StringIO.new('')

    assert_nil Prompt.read_single_char
  end

  def test_read_single_char_returns_q_on_interrupt
    $stdin = InterruptingStdin.new

    assert_equal 'q', Prompt.read_single_char
  end

  def test_prompt_for_action_writes_prompt_and_returns_input
    out = StringIO.new
    $stdin = StringIO.new("yes\n")
    $stdout = out

    result = Prompt.prompt_for_action('Continue?')

    assert_equal 'yes', result
    assert_includes out.string, 'Continue?'
    assert_includes out.string, ' > '
  end

  # Fake stdin that supports both tty? and raw
  class TtyStdin
    def initialize(char)
      @char = char
      @raw_called = false
    end

    def tty?
      true
    end

    def raw_called?
      @raw_called
    end

    def raw
      @raw_called = true
      yield self
    end

    def readchar
      @char
    end
  end

  # Fake stdin that raises Interrupt on tty?
  class InterruptingStdin
    def tty?
      raise Interrupt
    end
  end
end
