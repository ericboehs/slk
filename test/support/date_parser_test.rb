# frozen_string_literal: true

require_relative '../test_helper'

class DateParserTest < Minitest::Test
  def test_parse_days_duration
    now = Time.now.to_i
    result = Slk::Support::DateParser.parse('1d')

    # Should be approximately 1 day ago (within a few seconds)
    expected_min = now - (1 * 86_400) - 5
    expected_max = now - (1 * 86_400) + 5
    assert_includes (expected_min..expected_max), result
  end

  def test_parse_multiple_days_duration
    now = Time.now.to_i
    result = Slk::Support::DateParser.parse('7d')

    expected_min = now - (7 * 86_400) - 5
    expected_max = now - (7 * 86_400) + 5
    assert_includes (expected_min..expected_max), result
  end

  def test_parse_weeks_duration
    now = Time.now.to_i
    result = Slk::Support::DateParser.parse('2w')

    expected_min = now - (14 * 86_400) - 5
    expected_max = now - (14 * 86_400) + 5
    assert_includes (expected_min..expected_max), result
  end

  def test_parse_months_duration
    now = Time.now.to_i
    result = Slk::Support::DateParser.parse('1m')

    expected_min = now - (30 * 86_400) - 5
    expected_max = now - (30 * 86_400) + 5
    assert_includes (expected_min..expected_max), result
  end

  def test_parse_iso_date
    result = Slk::Support::DateParser.parse('2025-01-10')
    expected = Time.parse('2025-01-10 00:00:00').to_i
    assert_equal expected, result
  end

  def test_to_slack_timestamp_returns_string_with_microseconds
    result = Slk::Support::DateParser.to_slack_timestamp('1d')

    assert_match(/^\d+\.000000$/, result)
  end

  def test_duration_case_insensitive
    lower = Slk::Support::DateParser.parse('1d')
    upper = Slk::Support::DateParser.parse('1D')
    assert_equal lower, upper
  end

  def test_raises_on_invalid_format
    assert_raises(ArgumentError) do
      Slk::Support::DateParser.parse('invalid')
    end
  end

  def test_raises_on_invalid_duration_unit
    assert_raises(ArgumentError) do
      Slk::Support::DateParser.parse('5x')
    end
  end

  def test_raises_on_invalid_iso_date
    assert_raises(ArgumentError) do
      Slk::Support::DateParser.parse('2025-13-45')
    end
  end

  def test_handles_whitespace
    now = Time.now.to_i
    result = Slk::Support::DateParser.parse('  1d  ')

    expected_min = now - 86_400 - 5
    expected_max = now - 86_400 + 5
    assert_includes (expected_min..expected_max), result
  end
end
