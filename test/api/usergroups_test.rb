# frozen_string_literal: true

require "test_helper"

class UsergroupsApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace("test")
    @api = SlackCli::Api::Usergroups.new(@mock_client, @workspace)
  end

  def test_list_calls_api
    @mock_client.stub("usergroups.list", {
      "ok" => true,
      "usergroups" => [
        { "id" => "S123", "handle" => "platform-team" },
        { "id" => "S456", "handle" => "devops" }
      ]
    })

    result = @api.list
    assert result["ok"]
    assert_equal 2, result["usergroups"].size

    call = @mock_client.calls.last
    assert_equal "usergroups.list", call[:method]
    assert_equal "test", call[:workspace]
  end

  def test_get_handle_returns_handle_when_found
    @mock_client.stub("usergroups.list", {
      "ok" => true,
      "usergroups" => [
        { "id" => "S123", "handle" => "platform-team" },
        { "id" => "S456", "handle" => "devops" }
      ]
    })

    handle = @api.get_handle("S123")
    assert_equal "platform-team", handle
  end

  def test_get_handle_returns_nil_when_not_found
    @mock_client.stub("usergroups.list", {
      "ok" => true,
      "usergroups" => [
        { "id" => "S123", "handle" => "platform-team" }
      ]
    })

    handle = @api.get_handle("S999")
    assert_nil handle
  end

  def test_get_handle_returns_nil_when_api_fails
    @mock_client.stub("usergroups.list", {
      "ok" => false,
      "error" => "not_allowed"
    })

    handle = @api.get_handle("S123")
    assert_nil handle
  end

  def test_get_handle_returns_nil_when_no_usergroups
    @mock_client.stub("usergroups.list", {
      "ok" => true,
      "usergroups" => []
    })

    handle = @api.get_handle("S123")
    assert_nil handle
  end

  def test_get_handle_handles_missing_usergroups_key
    @mock_client.stub("usergroups.list", {
      "ok" => true
    })

    handle = @api.get_handle("S123")
    assert_nil handle
  end
end
