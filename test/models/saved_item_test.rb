# frozen_string_literal: true

require 'test_helper'

class SavedItemTest < Minitest::Test
  def test_basic_initialization
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    assert_equal 'C123', item.item_id
    assert_equal 'message', item.item_type
    assert_nil item.ts
    assert_equal 'saved', item.state
    refute item.is_archived
  end

  def test_full_initialization
    item = Slk::Models::SavedItem.new(
      item_id: 'C123',
      item_type: 'message',
      ts: '1234567890.123456',
      state: 'in_progress',
      date_created: 1_700_000_000,
      date_due: 1_700_100_000,
      date_completed: nil,
      is_archived: false
    )

    assert_equal 'C123', item.item_id
    assert_equal 'message', item.item_type
    assert_equal '1234567890.123456', item.ts
    assert_equal 'in_progress', item.state
    assert_equal 1_700_000_000, item.date_created
    assert_equal 1_700_100_000, item.date_due
    assert_nil item.date_completed
    refute item.is_archived
  end

  def test_from_api_creates_saved_item
    data = {
      'item_id' => 'C123',
      'item_type' => 'message',
      'ts' => '1234567890.123456',
      'state' => 'saved',
      'date_created' => 1_700_000_000,
      'date_due' => 1_700_100_000,
      'is_archived' => false
    }

    item = Slk::Models::SavedItem.from_api(data)

    assert_equal 'C123', item.item_id
    assert_equal 'message', item.item_type
    assert_equal '1234567890.123456', item.ts
    assert_equal 'saved', item.state
    assert_equal 1_700_000_000, item.date_created
    assert_equal 1_700_100_000, item.date_due
    refute item.is_archived
  end

  def test_from_api_uses_channel_id_fallback
    data = {
      'channel_id' => 'D456',
      'type' => 'message',
      'message_ts' => '1234567890.123456'
    }

    item = Slk::Models::SavedItem.from_api(data)

    assert_equal 'D456', item.item_id
  end

  def test_from_api_defaults_state_to_saved
    data = {
      'item_id' => 'C123',
      'item_type' => 'message'
    }

    item = Slk::Models::SavedItem.from_api(data)

    assert_equal 'saved', item.state
  end

  def test_channel_id_alias
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    assert_equal 'C123', item.channel_id
    assert_equal item.item_id, item.channel_id
  end

  def test_completed_predicate
    completed = Slk::Models::SavedItem.new(item_id: 'C123', state: 'completed')
    saved = Slk::Models::SavedItem.new(item_id: 'C123', state: 'saved')

    assert completed.completed?
    refute saved.completed?
  end

  def test_in_progress_predicate
    in_progress = Slk::Models::SavedItem.new(item_id: 'C123', state: 'in_progress')
    saved = Slk::Models::SavedItem.new(item_id: 'C123', state: 'saved')

    assert in_progress.in_progress?
    refute saved.in_progress?
  end

  def test_saved_predicate
    saved = Slk::Models::SavedItem.new(item_id: 'C123', state: 'saved')
    completed = Slk::Models::SavedItem.new(item_id: 'C123', state: 'completed')

    assert saved.saved?
    refute completed.saved?
  end

  def test_archived_predicate
    archived = Slk::Models::SavedItem.new(item_id: 'C123', is_archived: true)
    not_archived = Slk::Models::SavedItem.new(item_id: 'C123', is_archived: false)

    assert archived.archived?
    refute not_archived.archived?
  end

  def test_due_date_predicate
    with_due = Slk::Models::SavedItem.new(item_id: 'C123', date_due: 1_700_000_000)
    without_due = Slk::Models::SavedItem.new(item_id: 'C123')

    assert with_due.due_date?
    refute without_due.due_date?
  end

  def test_overdue_when_past_due_date
    past_due = Time.now.to_i - 3600 # 1 hour ago
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_due: past_due)

    assert item.overdue?
  end

  def test_not_overdue_when_future_due_date
    future_due = Time.now.to_i + 3600 # 1 hour from now
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_due: future_due)

    refute item.overdue?
  end

  def test_not_overdue_when_completed
    past_due = Time.now.to_i - 3600
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_due: past_due, state: 'completed')

    refute item.overdue?
  end

  def test_not_overdue_when_no_due_date
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    refute item.overdue?
  end

  def test_due_time_returns_time_object
    due_timestamp = 1_700_000_000
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_due: due_timestamp)

    assert_kind_of Time, item.due_time
    assert_equal due_timestamp, item.due_time.to_i
  end

  def test_due_time_returns_nil_when_no_due_date
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    assert_nil item.due_time
  end

  def test_created_time_returns_time_object
    created_timestamp = 1_700_000_000
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_created: created_timestamp)

    assert_kind_of Time, item.created_time
    assert_equal created_timestamp, item.created_time.to_i
  end

  def test_created_time_returns_nil_when_not_set
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    assert_nil item.created_time
  end

  def test_completed_time_returns_time_object
    completed_timestamp = 1_700_000_000
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_completed: completed_timestamp)

    assert_kind_of Time, item.completed_time
    assert_equal completed_timestamp, item.completed_time.to_i
  end

  def test_completed_time_returns_nil_when_not_set
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    assert_nil item.completed_time
  end

  def test_time_until_due_positive_for_future_due
    future_due = Time.now.to_i + 3600
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_due: future_due)

    time_until = item.time_until_due
    assert time_until.positive?
    assert time_until <= 3600
  end

  def test_time_until_due_negative_for_past_due
    past_due = Time.now.to_i - 3600
    item = Slk::Models::SavedItem.new(item_id: 'C123', date_due: past_due)

    assert item.time_until_due.negative?
  end

  def test_time_until_due_nil_when_no_due_date
    item = Slk::Models::SavedItem.new(item_id: 'C123')

    assert_nil item.time_until_due
  end

  def test_values_are_frozen
    item = Slk::Models::SavedItem.new(
      item_id: 'C123',
      item_type: 'message',
      ts: '1234567890.123456',
      state: 'saved'
    )

    assert item.item_id.frozen?
    assert item.item_type.frozen?
    assert item.ts.frozen?
    assert item.state.frozen?
  end

  def test_from_api_handles_zero_timestamps_as_nil
    data = {
      'item_id' => 'C123',
      'item_type' => 'message',
      'date_created' => 0,
      'date_due' => 0,
      'date_completed' => 0
    }

    item = Slk::Models::SavedItem.from_api(data)

    assert_nil item.date_created
    assert_nil item.date_due
    assert_nil item.date_completed
  end

  def test_from_api_handles_nil_timestamps
    data = {
      'item_id' => 'C123',
      'item_type' => 'message',
      'date_created' => nil,
      'date_due' => nil,
      'date_completed' => nil
    }

    item = Slk::Models::SavedItem.from_api(data)

    assert_nil item.date_created
    assert_nil item.date_due
    assert_nil item.date_completed
  end
end
