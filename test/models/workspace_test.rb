# frozen_string_literal: true

require "test_helper"

class WorkspaceTest < Minitest::Test
  def test_creates_with_required_fields
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxb-123")

    assert_equal "test", ws.name
    assert_equal "xoxb-123", ws.token
    assert_nil ws.cookie
  end

  def test_creates_with_cookie
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxc-123", cookie: "d=abc")

    assert_equal "d=abc", ws.cookie
  end

  def test_xoxb_detection
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxb-123")

    assert ws.xoxb?
    refute ws.xoxc?
    refute ws.xoxp?
  end

  def test_xoxc_detection
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxc-123")

    assert ws.xoxc?
    refute ws.xoxb?
    refute ws.xoxp?
  end

  def test_to_s_returns_name
    ws = SlackCli::Models::Workspace.new(name: "myworkspace", token: "xoxb-123")

    assert_equal "myworkspace", ws.to_s
  end

  def test_headers_include_authorization
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxb-123")
    headers = ws.headers

    assert_equal "Bearer xoxb-123", headers["Authorization"]
    assert_equal "application/json; charset=utf-8", headers["Content-Type"]
  end

  def test_headers_include_cookie_when_present
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxc-123", cookie: "d=abc")
    headers = ws.headers

    assert_equal "d=d=abc", headers["Cookie"]
  end

  def test_headers_exclude_cookie_when_nil
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxb-123")
    headers = ws.headers

    refute headers.key?("Cookie")
  end

  def test_immutable_name
    ws = SlackCli::Models::Workspace.new(name: "test", token: "xoxb-123")

    assert ws.name.frozen?
    assert ws.token.frozen?
  end
end
