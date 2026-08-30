# frozen_string_literal: true

require 'test_helper'

class DndStateTest < Minitest::Test
  def state(overrides = {})
    Slk::Models::DndState.from_api({ 'snooze_enabled' => false, 'snooze_endtime' => 0,
                                     'dnd_enabled' => false, 'next_dnd_start_ts' => 1,
                                     'next_dnd_end_ts' => 1 }.merge(overrides))
  end

  def test_quiet_when_nothing_is_holding_notifications
    refute_predicate state, :active?
    assert_nil state.source
    assert_empty state.to_s
  end

  def test_snooze_reports_when_it_lifts
    lifts = Time.now + (90 * 60)

    dnd = state('snooze_enabled' => true, 'snooze_endtime' => lifts.to_i)

    assert_predicate dnd, :active?
    assert_equal :snooze, dnd.source
    assert_equal lifts.to_i, dnd.until_time.to_i
    assert_match(/\A\[dnd until \d+:\d\d[ap]m\]\z/, dnd.to_s)
  end

  # Slack can report a snooze without an end time; claiming an hour that was
  # never promised is worse than admitting the end is unknown.
  def test_snooze_without_an_end_still_reports_dnd
    dnd = state('snooze_enabled' => true, 'snooze_endtime' => 0)

    assert_predicate dnd, :active?
    assert_equal '[dnd]', dnd.to_s
  end

  def test_scheduled_hours_count_while_they_are_running
    dnd = state('dnd_enabled' => true,
                'next_dnd_start_ts' => (Time.now - 3600).to_i,
                'next_dnd_end_ts' => (Time.now + 3600).to_i)

    assert_predicate dnd, :active?
    assert_equal :schedule, dnd.source
  end

  # `next_dnd_*` names the next window when DND hours are not running, so a
  # window that has not opened yet must not read as one that has.
  def test_scheduled_hours_starting_later_are_not_active
    dnd = state('dnd_enabled' => true,
                'next_dnd_start_ts' => (Time.now + 3600).to_i,
                'next_dnd_end_ts' => (Time.now + 7200).to_i)

    refute_predicate dnd, :active?
    assert_empty dnd.to_s
  end

  # Slack sends 1 for both timestamps when no schedule is configured. Read as
  # a real timestamp, that is a window that opened in 1970 and never closed.
  def test_the_no_schedule_sentinel_is_not_a_window
    refute_predicate state('dnd_enabled' => true), :active?
  end

  # Notifications resume when the last reason expires, not the first.
  def test_both_reasons_report_the_later_end
    schedule_end = Time.now + 7200

    dnd = state('snooze_enabled' => true, 'snooze_endtime' => (Time.now + 3600).to_i,
                'dnd_enabled' => true, 'next_dnd_start_ts' => (Time.now - 60).to_i,
                'next_dnd_end_ts' => schedule_end.to_i)

    assert_equal :both, dnd.source
    assert_equal schedule_end.to_i, dnd.until_time.to_i
  end

  # An overnight schedule ends tomorrow morning; a bare "until 8:00am" would
  # name a time that has already passed today.
  def test_an_end_on_another_day_carries_its_day
    tomorrow = Time.now + (20 * 3600)

    dnd = state('snooze_enabled' => true, 'snooze_endtime' => tomorrow.to_i)

    assert_equal tomorrow.strftime('%a %-l:%M%P'), dnd.until_label
  end

  # dnd.info is the least interesting endpoint to have changed shape, but a
  # nil here should read as "nothing on", not raise mid-status.
  def test_a_missing_payload_reads_as_off
    refute_predicate Slk::Models::DndState.from_api(nil), :active?
  end
end
