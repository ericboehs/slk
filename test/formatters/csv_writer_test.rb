# frozen_string_literal: true

require 'test_helper'

class CsvWriterTest < Minitest::Test
  def row(*values) = Slk::Formatters::CsvWriter.row(values)

  def test_plain_values_are_not_quoted
    assert_equal 'a,b,c', row('a', 'b', 'c')
  end

  def test_a_comma_forces_quotes
    assert_equal 'a,"b,c"', row('a', 'b,c')
  end

  def test_quotes_are_doubled_inside_a_quoted_field
    assert_equal '"say ""hi"""', row('say "hi"')
  end

  def test_newlines_survive_inside_a_field
    assert_equal %("line1\nline2"), row("line1\nline2")
  end

  def test_carriage_returns_are_quoted_too
    assert_equal %("a\rb"), row("a\rb")
  end

  # Leading and trailing spaces are meaningful in a name and a spreadsheet
  # will strip them unless they are quoted.
  def test_surrounding_whitespace_is_preserved
    assert_equal '" padded "', row(' padded ')
  end

  def test_nil_is_an_empty_cell_not_the_word_nil
    assert_equal 'a,,b', row('a', nil, 'b')
  end

  def test_booleans_and_numbers_render_as_themselves
    assert_equal 'true,false,42', row(true, false, 42)
  end

  def test_an_empty_row_is_an_empty_line
    assert_equal '', row
  end
end
