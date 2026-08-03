# frozen_string_literal: true

require 'test_helper'

class TimeParserTest < Minitest::Test
  # Fixed reference so "rolls forward" cases are deterministic.
  NOON = Time.new(2026, 8, 3, 12, 0, 0)

  def parse(input, now: NOON)
    Slk::Support::TimeParser.parse(input, now: now)
  end

  # DST cases only mean anything against a fixed zone; the suite otherwise
  # inherits whatever TZ the machine has.
  def with_timezone(zone)
    original = ENV.fetch('TZ', nil)
    ENV['TZ'] = zone
    yield
  ensure
    ENV['TZ'] = original
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
    error = assert_raises(ArgumentError) { parse('sometime tomorrow') }

    assert_includes error.message, 'Invalid time: sometime tomorrow'
    assert_includes error.message, Slk::Support::TimeParser::EXAMPLE
  end

  def test_rejects_nonexistent_calendar_date
    error = assert_raises(ArgumentError) { parse('2026-02-30 9:00') }

    assert_includes error.message, 'Invalid date: 2026-02-30'
  end

  def test_rejects_out_of_range_hour
    assert_raises(ArgumentError) { parse('25:00') }
  end

  def test_rejects_out_of_range_minute
    assert_raises(ArgumentError) { parse('1:75p') }
  end

  def test_rejects_zero_hour_with_meridiem
    assert_raises(ArgumentError) { parse('0p') }
  end

  # Ruby shifts a local time DST skips rather than raising, which would move
  # the schedule an hour without saying so.
  def test_rejects_local_time_skipped_by_dst
    with_timezone('America/Chicago') do
      error = assert_raises(ArgumentError) { parse('2026-03-08 2:30') }

      assert_includes error.message, 'does not exist'
    end
  end

  def test_match_identifies_single_times
    assert Slk::Support::TimeParser.match?('1:30p')
    assert Slk::Support::TimeParser.match?('2026-08-12 8:00')
  end

  def test_match_rejects_ranges_and_other_arguments
    refute Slk::Support::TimeParser.match?('1:30p-3:30p')
    refute Slk::Support::TimeParser.match?(':palm_tree:')
    refute Slk::Support::TimeParser.match?('OOO')
  end
end
