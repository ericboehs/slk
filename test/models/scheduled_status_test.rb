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

  # Api::CustomStatus sends is_dnd as the string 'true', so this endpoint
  # family is not reliably JSON-boolean. A strict `== true` read a scheduled
  # DND back as off, with no error to explain the missing [dnd] marker.
  def test_from_api_accepts_string_and_numeric_booleans
    status = build('is_dnd' => 'true', 'is_active' => 1)

    assert_equal true, status.dnd
    assert_equal true, status.active
  end

  def test_from_api_treats_unrecognized_values_as_false
    status = build('is_dnd' => 'false', 'is_active' => nil)

    assert_equal false, status.dnd
    assert_equal false, status.active
  end

  # Every field is coerced, so an unguarded payload of any shape would produce
  # a plausible-looking record with an empty id — one that prints as a blank
  # line and never matches the id a caller is searching for.
  def test_from_api_rejects_payloads_it_cannot_identify
    [nil, 'CS0BMQDDGWTU', [], {}, { 'id' => '' }, { 'text' => 'Vet Appt' }].each do |payload|
      error = assert_raises(Slk::ApiError) { Slk::Models::ScheduledStatus.from_api(payload) }

      assert_equal :malformed_scheduled_status, error.code
    end
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

  # The difference between "will happen" and "is happening" — the one entry in
  # a `slk status scheduled` list that is already showing on your profile.
  def test_to_s_flags_the_status_slack_has_already_applied
    assert_includes build('is_active' => true).to_s, '[active]'
    refute_includes build.to_s, '[active]'
  end
end
