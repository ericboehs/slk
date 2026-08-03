# frozen_string_literal: true

require 'test_helper'

class ScheduledStatusTest < Minitest::Test
  def api_payload(overrides = {})
    {
      'id' => 'CS0BMQDDGWTU',
      'user_id' => 'U01B0634XFT',
      'text' => 'Vet Appt',
      'emoji' => ':paw_prints:',
      'duration' => 'custom',
      'is_active' => false,
      'is_dnd' => false,
      'date_created' => 1_785_781_052,
      'date_scheduled' => Time.new(2026, 8, 3, 13, 30, 0).to_i,
      'date_expire' => Time.new(2026, 8, 3, 15, 30, 0).to_i
    }.merge(overrides)
  end

  def build(overrides = {})
    Slk::Models::ScheduledStatus.from_api(api_payload(overrides))
  end

  def test_from_api_maps_fields
    status = build

    assert_equal 'CS0BMQDDGWTU', status.id
    assert_equal 'Vet Appt', status.text
    assert_equal ':paw_prints:', status.emoji
    refute status.dnd
    refute status.active
  end

  def test_from_api_coerces_dnd_and_active_to_booleans
    status = build('is_dnd' => true, 'is_active' => true)

    assert_equal true, status.dnd
    assert_equal true, status.active
  end

  def test_from_api_tolerates_nil_payload
    status = Slk::Models::ScheduledStatus.from_api(nil)

    assert_equal '', status.id
    assert_equal 0, status.date_scheduled
    refute status.dnd
  end

  def test_from_api_tolerates_missing_keys
    status = Slk::Models::ScheduledStatus.from_api({ 'id' => 'CS1' })

    assert_equal 'CS1', status.id
    assert_equal '', status.text
    assert_equal 0, status.date_expire
  end

  def test_starts_at_and_ends_at_convert_to_times
    status = build

    assert_equal Time.new(2026, 8, 3, 13, 30, 0), status.starts_at
    assert_equal Time.new(2026, 8, 3, 15, 30, 0), status.ends_at
  end

  def test_starts_at_is_nil_when_unset
    assert_nil build('date_scheduled' => 0).starts_at
    assert_nil build('date_expire' => 0).ends_at
  end

  def test_window_omits_repeated_date_within_one_day
    window = build.window

    assert_includes window, 'Mon Aug 3 1:30pm'
    assert_includes window, '-> 3:30pm'
    # The end date is same-day, so it should not be spelled out again.
    refute_includes window, '-> Mon Aug 3'
  end

  def test_window_spells_out_end_date_when_it_differs
    window = build('date_expire' => Time.new(2026, 8, 4, 15, 30, 0).to_i).window

    assert_includes window, '-> Tue Aug 4 3:30pm'
  end

  def test_window_without_end_shows_only_start
    assert_equal 'Mon Aug 3 1:30pm', build('date_expire' => 0).window
  end

  def test_window_is_blank_without_start
    assert_equal '', build('date_scheduled' => 0).window
  end

  def test_to_s_includes_emoji_text_and_window
    string = build.to_s

    assert_includes string, ':paw_prints:'
    assert_includes string, 'Vet Appt'
    assert_includes string, '1:30pm'
  end

  def test_to_s_omits_blank_emoji_and_text
    assert_equal build('emoji' => '').to_s, "Vet Appt (#{build.window})"
    refute_includes build('text' => '').to_s, 'Vet Appt'
  end

  def test_to_s_without_a_window
    assert_equal ':paw_prints: Vet Appt', build('date_scheduled' => 0, 'date_expire' => 0).to_s
  end

  def test_to_s_flags_dnd
    assert_includes build('is_dnd' => true).to_s, '[dnd]'
    refute_includes build.to_s, '[dnd]'
  end
end
