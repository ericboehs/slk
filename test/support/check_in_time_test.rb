# frozen_string_literal: true

require 'test_helper'

class CheckInTimeTest < Minitest::Test
  def setup
    @now = Time.local(2026, 9, 22, 16, 30)
  end

  def test_local_clock_and_iso_without_offset
    assert_equal Time.local(2026, 9, 22, 15, 17), parse('15:17')
    assert_equal Time.local(2026, 9, 22, 15, 17), parse('2026-09-22T15:17')
    assert_equal Time.local(2026, 9, 22, 15, 17, 4), parse('2026-09-22T15:17:04')
  end

  def test_future_clock_uses_previous_local_calendar_day
    now = Time.local(2026, 9, 23, 2, 0)
    assert_equal Time.local(2026, 9, 22, 16, 0), Slk::Support::CheckInTime.parse('16:00', now: now)
    assert_equal Time.local(2025, 12, 31, 16, 0),
                 Slk::Support::CheckInTime.parse('16:00', now: Time.local(2026, 1, 1, 2, 0))
  end

  def test_clock_uses_today_if_time_has_arrived
    assert_equal Time.local(2026, 9, 22, 16, 0), parse('16:00')
    assert_equal Time.local(2026, 9, 22, 16, 30), parse('16:30')
    assert_equal Time.local(2026, 9, 21, 16, 31), parse('16:31')
  end

  def test_relative_minutes_hours_and_days
    assert_equal @now - 5400, parse('90m')
    assert_equal @now - 7200, parse('2h')
    assert_equal @now - 86_400, parse('1d')
  end

  def test_epoch_and_slack_microseconds
    time = Time.at(1_790_000_000, 123_456)
    assert_equal time, parse('1790000000.123456')
    assert_equal '1790000000.123456', Slk::Support::CheckInTime.timestamp(time)
    assert_equal Time.at(1_790_000_000), parse('1790000000')
  end

  def test_iso_with_offset
    # An explicit offset names an absolute instant, so compare against an
    # absolute `now`; a Time.local `now` shifts with the runner's TZ (CI is UTC).
    now = Time.iso8601('2026-09-22T16:30:00-05:00')
    assert_equal Time.iso8601('2026-09-22T15:17:00-05:00'),
                 Slk::Support::CheckInTime.parse('2026-09-22T15:17-05:00', now: now)
    assert_equal Time.iso8601('2026-09-22T20:17:00Z'),
                 Slk::Support::CheckInTime.parse('2026-09-22T20:17Z', now: now)
  end

  def test_rejects_invalid_and_future_times
    %w[25:00 12:60 2026-09-22T17:00 0m 2026-02-30T15:00 nope].each do |value|
      assert_raises(Slk::UsageError) { parse(value) }
    end
  end

  private

  def parse(value)
    Slk::Support::CheckInTime.parse(value, now: @now)
  end
end
