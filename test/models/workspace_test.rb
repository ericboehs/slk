# frozen_string_literal: true

require 'test_helper'

class WorkspaceTest < Minitest::Test
  def test_creates_with_required_fields
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-123')

    assert_equal 'test', ws.name
    assert_equal 'xoxb-123', ws.token
    assert_nil ws.cookie
  end

  def test_creates_with_cookie
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123', cookie: 'abc')

    assert_equal 'abc', ws.cookie
  end

  def test_xoxb_detection
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-123')

    assert ws.xoxb?
    refute ws.xoxc?
    refute ws.xoxp?
  end

  def test_xoxc_detection
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123', cookie: 'abc')

    assert ws.xoxc?
    refute ws.xoxb?
    refute ws.xoxp?
  end

  def test_xoxp_detection
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxp-123')

    assert ws.xoxp?
    refute ws.xoxb?
    refute ws.xoxc?
  end

  def test_to_s_returns_name
    ws = SlackCli::Models::Workspace.new(name: 'myworkspace', token: 'xoxb-123')

    assert_equal 'myworkspace', ws.to_s
  end

  def test_headers_include_authorization
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-123')
    headers = ws.headers

    assert_equal 'Bearer xoxb-123', headers['Authorization']
    assert_equal 'application/json; charset=utf-8', headers['Content-Type']
  end

  def test_headers_include_cookie_when_present
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123', cookie: 'abc')
    headers = ws.headers

    assert_equal 'd=abc', headers['Cookie']
  end

  def test_headers_exclude_cookie_when_nil
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-123')
    headers = ws.headers

    refute headers.key?('Cookie')
  end

  def test_immutable_name
    ws = SlackCli::Models::Workspace.new(name: 'test', token: 'xoxb-123')

    assert ws.name.frozen?
    assert ws.token.frozen?
  end

  # Validation tests

  def test_raises_on_empty_name
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: '', token: 'xoxb-123')
    end
    assert_match(/name cannot be empty/, error.message)
  end

  def test_raises_on_whitespace_only_name
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: '   ', token: 'xoxb-123')
    end
    assert_match(/name cannot be empty/, error.message)
  end

  def test_raises_on_name_with_path_separators
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: '../etc', token: 'xoxb-123')
    end
    assert_match(/invalid characters/, error.message)
  end

  def test_raises_on_invalid_token_format
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: 'test', token: 'invalid-token')
    end
    assert_match(/invalid token format/, error.message)
  end

  def test_raises_on_xoxc_without_cookie
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123')
    end
    assert_match(/xoxc tokens require a cookie/, error.message)
  end

  def test_raises_on_xoxc_with_empty_cookie
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123', cookie: '')
    end
    assert_match(/xoxc tokens require a cookie/, error.message)
  end

  def test_raises_on_cookie_with_newline
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123', cookie: "value\ninjected")
    end
    assert_match(/cannot contain newlines/, error.message)
  end

  def test_raises_on_cookie_with_carriage_return
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Workspace.new(name: 'test', token: 'xoxc-123', cookie: "value\rinjected")
    end
    assert_match(/cannot contain newlines/, error.message)
  end
end
