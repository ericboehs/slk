# frozen_string_literal: true

require 'test_helper'

class TimeRangeParserTest < Minitest::Test
  # Fixed reference so "rolls forward" cases are deterministic.
  NOON = Time.new(2026, 8, 3, 12, 0, 0)

  def parse(input, now: NOON)
    Slk::Support::TimeRangeParser.parse(input, now: now)
  end

  def test_parses_twelve_hour_range_on_the_same_day
    starts_at, ends_at = parse('1:30p-3:30p')

    assert_equal Time.new(2026, 8, 3, 13, 30, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 3, 15, 30, 0).to_i, ends_at
  end

  def test_parses_twenty_four_hour_range
    starts_at, ends_at = parse('13:30-15:30')

    assert_equal Time.new(2026, 8, 3, 13, 30, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 3, 15, 30, 0).to_i, ends_at
  end

  def test_accepts_full_meridiem_suffix
    starts_at, = parse('1:30pm-3:30pm')

    assert_equal Time.new(2026, 8, 3, 13, 30, 0).to_i, starts_at
  end

  def test_omitted_minutes_default_to_zero
    starts_at, ends_at = parse('2p-4p')

    assert_equal Time.new(2026, 8, 3, 14, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 3, 16, 0, 0).to_i, ends_at
  end

  def test_bare_time_already_past_rolls_to_tomorrow
    starts_at, ends_at = parse('1:30p-3:30p', now: Time.new(2026, 8, 3, 14, 0, 0))

    assert_equal Time.new(2026, 8, 4, 13, 30, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 15, 30, 0).to_i, ends_at
  end

  def test_explicit_date_is_used_verbatim_even_when_past
    starts_at, ends_at = parse('2026-08-01 09:00-17:00')

    assert_equal Time.new(2026, 8, 1, 9, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 1, 17, 0, 0).to_i, ends_at
  end

  def test_overnight_window_rolls_end_to_next_day
    starts_at, ends_at = parse('11p-1a')

    assert_equal Time.new(2026, 8, 3, 23, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 1, 0, 0).to_i, ends_at
  end

  def test_noon_and_midnight_meridiems
    starts_at, ends_at = parse('12p-12a')

    assert_equal Time.new(2026, 8, 3, 12, 0, 0).to_i + 86_400, starts_at
    assert_equal Time.new(2026, 8, 5, 0, 0, 0).to_i, ends_at
  end

  def test_rejects_unparseable_input
    error = assert_raises(ArgumentError) { parse('sometime tomorrow') }
    assert_includes error.message, 'Invalid time range'
  end

  def test_rejects_out_of_range_hour
    assert_raises(ArgumentError) { parse('25:00-26:00') }
  end

  def test_rejects_out_of_range_minute
    assert_raises(ArgumentError) { parse('1:75p-3:30p') }
  end

  def test_rejects_zero_hour_with_meridiem
    assert_raises(ArgumentError) { parse('0p-3p') }
  end

  def test_match_identifies_ranges
    assert Slk::Support::TimeRangeParser.match?('1:30p-3:30p')
    assert Slk::Support::TimeRangeParser.match?('2026-08-04 13:30-15:30')
  end

  def test_match_rejects_non_ranges
    refute Slk::Support::TimeRangeParser.match?(':paw_prints:')
    refute Slk::Support::TimeRangeParser.match?('Vet Appt')
    refute Slk::Support::TimeRangeParser.match?('2h')
  end
end
