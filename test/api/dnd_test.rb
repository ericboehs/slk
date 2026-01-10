# frozen_string_literal: true

require "test_helper"

class DndApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace("test")
    @api = SlackCli::Api::Dnd.new(@mock_client, @workspace)
  end

  def test_info_calls_api
    @mock_client.stub("dnd.info", {
      "ok" => true,
      "dnd_enabled" => true,
      "next_dnd_start_ts" => 1234567890,
      "next_dnd_end_ts" => 1234571490,
      "snooze_enabled" => false
    })

    result = @api.info
    assert result["dnd_enabled"]
    assert_equal 1234567890, result["next_dnd_start_ts"]

    call = @mock_client.calls.last
    assert_equal "dnd.info", call[:method]
  end

  def test_set_snooze_with_duration
    @mock_client.stub("dnd.setSnooze", {
      "ok" => true,
      "snooze_enabled" => true,
      "snooze_endtime" => Time.now.to_i + 3600
    })

    duration = SlackCli::Models::Duration.new(seconds: 3600)
    result = @api.set_snooze(duration)
    assert result["snooze_enabled"]

    call = @mock_client.calls.last
    assert_equal "dnd.setSnooze", call[:method]
    assert_equal 60, call[:params][:num_minutes]
  end

  def test_end_snooze_calls_api
    @mock_client.stub("dnd.endSnooze", { "ok" => true })

    @api.end_snooze

    call = @mock_client.calls.last
    assert_equal "dnd.endSnooze", call[:method]
  end

  def test_snoozing_returns_true_when_enabled
    @mock_client.stub("dnd.info", {
      "ok" => true,
      "snooze_enabled" => true
    })

    assert @api.snoozing?
  end

  def test_snoozing_returns_false_when_disabled
    @mock_client.stub("dnd.info", {
      "ok" => true,
      "snooze_enabled" => false
    })

    refute @api.snoozing?
  end

  def test_snooze_remaining_returns_duration_when_snoozing
    endtime = Time.now.to_i + 1800
    @mock_client.stub("dnd.info", {
      "ok" => true,
      "snooze_enabled" => true,
      "snooze_endtime" => endtime
    })

    remaining = @api.snooze_remaining
    assert_kind_of SlackCli::Models::Duration, remaining
  end

  def test_snooze_remaining_returns_nil_when_not_snoozing
    @mock_client.stub("dnd.info", {
      "ok" => true,
      "snooze_enabled" => false
    })

    assert_nil @api.snooze_remaining
  end
end
