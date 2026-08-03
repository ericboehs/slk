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

  def test_bare_start_borrows_the_end_meridiem
    starts_at, ends_at = parse('1-3p')

    assert_equal Time.new(2026, 8, 3, 13, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 3, 15, 0, 0).to_i, ends_at
  end

  # 10a has passed at the noon reference, so the whole window rolls forward.
  def test_bare_end_borrows_the_start_meridiem
    starts_at, ends_at = parse('10a-11')

    assert_equal Time.new(2026, 8, 4, 10, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 11, 0, 0).to_i, ends_at
  end

  # Borrowing "p" would make 9pm-5pm, so 9 stays the 24-hour hour it looks like.
  def test_meridiem_is_not_borrowed_when_it_would_invert_the_range
    starts_at, ends_at = parse('9-5p')

    assert_equal Time.new(2026, 8, 4, 9, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 17, 0, 0).to_i, ends_at
  end

  # "10p-2" is 10pm to 2am; borrowing "p" would invert it.
  def test_bare_end_keeps_overnight_window_when_borrowing_would_invert
    starts_at, ends_at = parse('10p-2')

    assert_equal Time.new(2026, 8, 3, 22, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 2, 0, 0).to_i, ends_at
  end

  # 13 is not a 12-hour clock hour, so there is nothing to borrow into.
  def test_twenty_four_hour_start_ignores_the_end_meridiem
    starts_at, ends_at = parse('13-3p')

    assert_equal Time.new(2026, 8, 3, 13, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 3, 15, 0, 0).to_i, ends_at
  end

  # Neither side names a meridiem, so "5" is 05:00 and the window rolls a full
  # night. Silently scheduling 20 hours is worse than asking for am/pm.
  def test_rejects_overlong_window_created_by_rollover
    error = assert_raises(Slk::TimeFormatError) { parse('9-5') }

    assert_includes error.message, 'spans 20 hours'
    assert_includes error.message, '9a-5p'
  end

  # The likeliest form of the mistake: the am/pm is there, but on the side
  # that did not need it. The borrow is declined because 5am precedes 9am, so
  # "5" falls back to 05:00 and the window silently runs 20 hours.
  def test_rejects_overlong_window_when_the_meridiem_is_on_the_wrong_side
    { '9a-5' => '20 hours', '10a-6' => '20 hours', '11a-1' => '14 hours' }.each do |range, span|
      error = assert_raises(Slk::TimeFormatError) { parse(range) }

      assert_includes error.message, span
    end
  end

  # Mirror image: the bare side is the start, and "10" falls back to 10:00.
  def test_rejects_overlong_window_when_the_bare_side_is_the_start
    error = assert_raises(Slk::TimeFormatError) { parse('10-5a') }

    assert_includes error.message, 'spans 19 hours'
  end

  # A pm start says "overnight" clearly enough that the bare end can only be
  # the next morning. These are the shifts the rule must not catch.
  def test_allows_overnight_window_implied_by_a_pm_start
    { '9p-5' => 5, '10p-9' => 9, '10p-2' => 2 }.each do |range, end_hour|
      _, ends_at = parse(range)

      assert_equal Time.new(2026, 8, 4, end_hour, 0, 0).to_i, ends_at
    end
  end

  # A 24-hour time on either side settles how to read the other, so nothing is
  # guessed and the length is the user's business.
  def test_allows_bare_end_anchored_by_a_twenty_four_hour_start
    starts_at, ends_at = parse('20:00-6')

    assert_equal Time.new(2026, 8, 3, 20, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 6, 0, 0).to_i, ends_at
  end

  # The bound exists to catch a *missing* am/pm. These say exactly what they
  # mean, so a 13-hour night is the user's call, not a typo to second-guess.
  def test_allows_long_overnight_window_when_the_meridiem_is_explicit
    starts_at, ends_at = parse('8p-9a')

    assert_equal Time.new(2026, 8, 3, 20, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 9, 0, 0).to_i, ends_at
  end

  # A single hour above 12 fixes the whole range as 24-hour notation, so "09:00"
  # here cannot have been a dropped "9pm".
  def test_allows_long_overnight_window_written_in_twenty_four_hour_time
    starts_at, ends_at = parse('2026-08-04 20:00-09:00')

    assert_equal Time.new(2026, 8, 4, 20, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 5, 9, 0, 0).to_i, ends_at
  end

  # Same 20-hour mistake as "9-5", just written with minutes.
  def test_rejects_overlong_window_when_neither_side_disambiguates
    error = assert_raises(Slk::TimeFormatError) { parse('9:00-5:00') }

    assert_includes error.message, 'spans 20 hours'
  end

  # The narrowest ambiguous crossing there is. Reported to the minute rather
  # than rounded down to a tidy "12 hours".
  def test_reports_an_uneven_span_without_rounding
    error = assert_raises(Slk::TimeFormatError) { parse('12:59-1:00') }

    assert_includes error.message, '12h01m'
  end

  def test_allows_long_window_within_a_single_day
    starts_at, ends_at = parse('2026-08-04 0:00-23:00')

    assert_equal Time.new(2026, 8, 4, 0, 0, 0).to_i, starts_at
    assert_equal Time.new(2026, 8, 4, 23, 0, 0).to_i, ends_at
  end

  def test_rejects_identical_start_and_end
    error = assert_raises(Slk::TimeFormatError) { parse('1p-1p') }

    assert_includes error.message, 'starts and ends at the same time'
  end

  # Ruby shifts a local time DST skips rather than raising, which previously
  # collapsed the window onto the start and rolled it a full day.
  def test_rejects_local_time_skipped_by_dst
    with_timezone('America/Chicago', expected_offset: CHICAGO_WINTER_OFFSET) do
      error = assert_raises(Slk::TimeFormatError) { parse('2026-03-08 2:30-3:30') }

      assert_includes error.message, 'does not exist'
    end
  end

  def test_overnight_window_across_spring_forward_stays_short
    with_timezone('America/Chicago', expected_offset: CHICAGO_WINTER_OFFSET) do
      starts_at, ends_at = parse('2026-03-07 11p-1a')

      assert_equal Time.new(2026, 3, 7, 23, 0, 0).to_i, starts_at
      assert_equal Time.new(2026, 3, 8, 1, 0, 0).to_i, ends_at
    end
  end

  # Date arithmetic, not +86_400, so the roll survives a DST boundary.
  def test_roll_to_tomorrow_across_spring_forward_keeps_wall_clock_time
    with_timezone('America/Chicago', expected_offset: CHICAGO_WINTER_OFFSET) do
      starts_at, = parse('9a-5p', now: Time.new(2026, 3, 7, 10, 0, 0))

      assert_equal Time.new(2026, 3, 8, 9, 0, 0).to_i, starts_at
    end
  end

  def test_rejects_nonexistent_calendar_date
    error = assert_raises(Slk::TimeFormatError) { parse('2026-02-30 9:00-10:00') }

    assert_includes error.message, 'Invalid date: 2026-02-30'
    assert_includes error.message, Slk::Support::TimeRangeParser::EXAMPLE
  end

  def test_rejects_unparseable_input
    error = assert_raises(Slk::TimeFormatError) { parse('sometime tomorrow') }
    assert_includes error.message, 'Invalid time range'
  end

  def test_rejects_out_of_range_hour
    assert_raises(Slk::TimeFormatError) { parse('25:00-26:00') }
  end

  def test_rejects_out_of_range_minute
    assert_raises(Slk::TimeFormatError) { parse('1:75p-3:30p') }
  end

  def test_rejects_zero_hour_with_meridiem
    assert_raises(Slk::TimeFormatError) { parse('0p-3p') }
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
