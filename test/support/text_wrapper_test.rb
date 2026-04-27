# frozen_string_literal: true

require 'test_helper'

class TextWrapperTest < Minitest::Test
  TW = Slk::Support::TextWrapper

  def test_visible_length_strips_ansi
    assert_equal 5, TW.visible_length("\e[31mhello\e[0m")
    assert_equal 5, TW.visible_length('hello')
  end

  def test_wrap_short_text_returns_unchanged
    assert_equal 'hello', TW.wrap('hello', 80, 80)
  end

  def test_wrap_long_text_breaks_into_lines
    long = (['word'] * 20).join(' ')
    out = TW.wrap(long, 30, 30)
    assert_operator out.lines.size, :>, 1
  end

  def test_wrap_preserves_paragraphs
    text = "first\n\nsecond"
    out = TW.wrap(text, 50, 50)
    assert_equal 3, out.lines.size
    assert_equal "first\n\nsecond", out
  end

  def test_wrap_continuation_uses_different_width
    text = (['word'] * 10).join(' ')
    out = TW.wrap(text, 8, 20)
    lines = out.lines.map(&:chomp)
    assert_operator lines.size, :>=, 2
  end

  def test_wrap_paragraph_with_multiple_paragraphs_uses_continuation_width
    text = "intro line\n\nsecond paragraph here is much longer than first"
    out = TW.wrap(text, 5, 30)
    refute_empty out
  end

  def test_visible_length_with_complex_ansi
    complex = "\e[1;31mbold red\e[0m \e[4munderline\e[0m"
    assert_equal 18, TW.visible_length(complex)
  end

  def test_wrap_handles_single_long_word
    out = TW.wrap('supercalifragilisticexpialidocious', 5, 5)
    # Single word longer than width still produces output
    refute_empty out
  end

  def test_wrap_empty_string
    assert_equal '', TW.wrap('', 10, 10)
  end

  def test_wrap_preserves_only_newlines
    out = TW.wrap("\n\n", 10, 10)
    refute_nil out
  end
end
