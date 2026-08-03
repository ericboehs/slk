# frozen_string_literal: true

require 'test_helper'

class TimeParserTest < Minitest::Test
  # Fixed reference so "rolls forward" cases are deterministic.
  NOON = Time.new(2026, 8, 3, 12, 0, 0)

  def parse(input, now: NOON)
    Slk::Support::TimeParser.parse(input, now: now)
  end

  def test_parses_bare_twelve_hour_time
    assert_equal Time.new(2026, 8, 3, 14, 0, 0).to_i, parse('2p')
  end

  def test_parses_bare_twenty_four_hour_time
    assert_equal Time.new(2026, 8, 3, 13, 30, 0).to_i, parse('13:30')
  end

  def test_bare_time_at_or_before_now_rolls_to_tomorrow
    assert_equal Time.new(2026, 8, 4, 8, 0, 0).to_i, parse('8a')
    assert_equal Time.new(2026, 8, 4, 12, 0, 0).to_i, parse('12p')
  end

  # The whole point of the flag form: a date days out is honoured as given.
  def test_explicit_date_is_used_verbatim
    assert_equal Time.new(2026, 8, 12, 8, 0, 0).to_i, parse('2026-08-12 8a')
    assert_equal Time.new(2026, 8, 14, 17, 0, 0).to_i, parse('2026-08-14 17:00')
  end

  def test_explicit_date_in_the_past_is_not_rolled_forward
    assert_equal Time.new(2026, 8, 1, 9, 0, 0).to_i, parse('2026-08-01 9a')
  end

  def test_rejects_unparseable_input
    error = assert_raises(Slk::TimeFormatError) { parse('sometime tomorrow') }

    assert_includes error.message, 'Invalid time: sometime tomorrow'
    assert_includes error.message, Slk::Support::TimeParser::EXAMPLE
  end

  def test_rejects_nonexistent_calendar_date
    error = assert_raises(Slk::TimeFormatError) { parse('2026-02-30 9:00') }

    assert_includes error.message, 'Invalid date: 2026-02-30'
  end

  def test_rejects_out_of_range_hour
    assert_raises(Slk::TimeFormatError) { parse('25:00') }
  end

  def test_rejects_out_of_range_minute
    assert_raises(Slk::TimeFormatError) { parse('1:75p') }
  end

  def test_rejects_zero_hour_with_meridiem
    assert_raises(Slk::TimeFormatError) { parse('0p') }
  end

  # Ruby shifts a local time DST skips rather than raising, which would move
  # the schedule an hour without saying so.
  def test_rejects_local_time_skipped_by_dst
    with_timezone('America/Chicago', expected_offset: CHICAGO_WINTER_OFFSET) do
      error = assert_raises(Slk::TimeFormatError) { parse('2026-03-08 2:30') }

      assert_includes error.message, 'does not exist'
    end
  end
end
