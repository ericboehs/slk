# frozen_string_literal: true

require "test_helper"

class UsersApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace("test")
    @api = SlackCli::Api::Users.new(@mock_client, @workspace)
  end

  def test_get_profile_calls_api
    @mock_client.stub("users.profile.get", {
      "ok" => true,
      "profile" => {
        "status_text" => "Working",
        "status_emoji" => ":computer:",
        "display_name" => "John"
      }
    })

    profile = @api.get_profile
    assert_equal "Working", profile["status_text"]
    assert_equal ":computer:", profile["status_emoji"]

    call = @mock_client.calls.last
    assert_equal "users.profile.get", call[:method]
    assert_equal "test", call[:workspace]
  end

  def test_get_status_returns_status_model
    @mock_client.stub("users.profile.get", {
      "ok" => true,
      "profile" => {
        "status_text" => "Lunch",
        "status_emoji" => ":fork_and_knife:",
        "status_expiration" => Time.now.to_i + 3600
      }
    })

    status = @api.get_status
    assert_kind_of SlackCli::Models::Status, status
    assert_equal "Lunch", status.text
    assert_equal ":fork_and_knife:", status.emoji
    assert status.expires?
  end

  def test_set_status_sends_profile
    @mock_client.stub("users.profile.set", { "ok" => true })

    duration = SlackCli::Models::Duration.new(seconds: 3600)
    @api.set_status(text: "Meeting", emoji: ":calendar:", duration: duration)

    call = @mock_client.calls.last
    assert_equal "users.profile.set", call[:method]
    assert_equal "Meeting", call[:params][:profile][:status_text]
    assert_equal ":calendar:", call[:params][:profile][:status_emoji]
    assert call[:params][:profile][:status_expiration] > 0
  end

  def test_clear_status
    @mock_client.stub("users.profile.set", { "ok" => true })

    @api.clear_status

    call = @mock_client.calls.last
    assert_equal "", call[:params][:profile][:status_text]
    assert_equal "", call[:params][:profile][:status_emoji]
  end

  def test_get_presence
    @mock_client.stub("users.getPresence", {
      "ok" => true,
      "presence" => "active",
      "manual_away" => false,
      "online" => true
    })

    result = @api.get_presence
    assert_equal "active", result[:presence]
    assert_equal false, result[:manual_away]
    assert_equal true, result[:online]
  end

  def test_set_presence
    @mock_client.stub("users.setPresence", { "ok" => true })

    @api.set_presence("away")

    call = @mock_client.calls.last
    assert_equal "users.setPresence", call[:method]
    assert_equal "away", call[:params][:presence]
  end

  def test_list_users
    @mock_client.stub("users.list", {
      "ok" => true,
      "members" => [
        { "id" => "U123", "name" => "alice" },
        { "id" => "U456", "name" => "bob" }
      ]
    })

    result = @api.list
    assert_equal 2, result["members"].size
    assert_equal "alice", result["members"][0]["name"]
  end

  def test_muted_channels_from_legacy_format
    @mock_client.stub("users.prefs.get", {
      "ok" => true,
      "prefs" => {
        "muted_channels" => "C123,C456,C789"
      }
    })

    muted = @api.muted_channels
    assert_equal %w[C123 C456 C789], muted
  end

  def test_muted_channels_from_new_format
    notifications = {
      "channels" => {
        "C123" => { "muted" => true },
        "C456" => { "muted" => false },
        "C789" => { "muted" => true }
      }
    }
    @mock_client.stub("users.prefs.get", {
      "ok" => true,
      "prefs" => {
        "muted_channels" => nil,
        "all_notifications_prefs" => JSON.generate(notifications)
      }
    })

    muted = @api.muted_channels
    assert_includes muted, "C123"
    assert_includes muted, "C789"
    refute_includes muted, "C456"
  end

  def test_muted_channels_returns_empty_when_no_data
    @mock_client.stub("users.prefs.get", {
      "ok" => true,
      "prefs" => {}
    })

    muted = @api.muted_channels
    assert_equal [], muted
  end
end
