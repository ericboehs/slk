# frozen_string_literal: true

require 'test_helper'

class DeactivationModelTest < Minitest::Test
  def member(overrides = {})
    {
      'id' => 'U1', 'name' => 'jane.doe', 'updated' => 1_700_000_000,
      'profile' => { 'real_name' => 'Jane Doe', 'title' => 'Engineer', 'email' => 'jane@example.com' }
    }.merge(overrides)
  end

  def test_from_api_maps_profile_fields
    record = Slk::Models::Deactivation.from_api(member)

    assert_equal 'U1', record.user_id
    assert_equal 'jane.doe', record.handle
    assert_equal 'Jane Doe', record.real_name
    assert_equal 'Engineer', record.title
    assert_equal 'jane@example.com', record.email
    assert_equal 1_700_000_000, record.deactivated_at
    refute record.bot
  end

  def test_bots_and_app_users_are_flagged
    assert Slk::Models::Deactivation.from_api(member('is_bot' => true)).bot
    assert Slk::Models::Deactivation.from_api(member('is_app_user' => true)).bot
    assert Slk::Models::Deactivation.from_api(member('id' => 'USLACKBOT')).bot
  end

  # A missing or zero `updated` means Slack never told us when; that has to
  # read as unknown rather than as a 1970 departure.
  def test_missing_timestamp_is_nil_not_epoch_zero
    record = Slk::Models::Deactivation.from_api(member('updated' => 0))

    assert_nil record.deactivated_at
    assert_nil record.date
    assert_nil record.month
  end

  def test_cache_round_trip_preserves_fields
    original = Slk::Models::Deactivation.from_api(member)
    restored = Slk::Models::Deactivation.from_cache(JSON.parse(JSON.generate(original.to_cache)))

    assert_equal original, restored
  end

  def test_best_name_falls_back_to_handle_then_id
    profileless = Slk::Models::Deactivation.from_api({ 'id' => 'U2', 'name' => 'ghost', 'updated' => 1 })
    nameless = Slk::Models::Deactivation.from_api({ 'id' => 'U3', 'updated' => 1 })

    assert_equal 'ghost', profileless.best_name
    assert_equal 'U3', nameless.best_name
  end

  def test_matches_searches_every_field
    record = Slk::Models::Deactivation.from_api(member)

    assert record.matches?(/engineer/i)
    assert record.matches?(/jane\.doe/i)
    assert record.matches?(/example\.com/i)
    refute record.matches?(/plumber/i)
  end

  def test_date_and_month_use_local_time
    record = Slk::Models::Deactivation.from_api(member('updated' => Time.new(2026, 3, 4, 12, 0, 0).to_i))

    assert_equal '2026-03-04', record.date
    assert_equal '2026-03', record.month
  end
end
