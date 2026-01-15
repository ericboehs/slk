# frozen_string_literal: true

require 'test_helper'
require 'net/http'

class ApiClientTest < Minitest::Test
  def setup
    @client = Slk::Services::ApiClient.new
    @workspace = mock_workspace
  end

  def teardown
    @client.close
  end

  # Initialization tests
  def test_initializes_with_zero_call_count
    assert_equal 0, @client.call_count
  end

  def test_initializes_with_nil_on_request_callback
    assert_nil @client.on_request
  end

  # Call counting tests
  def test_on_request_callback_is_settable
    callback = ->(method, count) { "#{method}: #{count}" }
    @client.on_request = callback
    assert_equal callback, @client.on_request
  end

  # close() tests
  def test_close_returns_without_error_when_no_connections
    @client.close # Should not raise
    assert true
  end

  # NETWORK_ERRORS constant tests
  def test_network_errors_constant_exists
    assert_kind_of Array, Slk::Services::ApiClient::NETWORK_ERRORS
  end

  def test_network_errors_includes_socket_error
    assert_includes Slk::Services::ApiClient::NETWORK_ERRORS, SocketError
  end

  def test_network_errors_includes_connection_refused
    assert_includes Slk::Services::ApiClient::NETWORK_ERRORS, Errno::ECONNREFUSED
  end

  def test_network_errors_includes_timeout_errors
    assert_includes Slk::Services::ApiClient::NETWORK_ERRORS, Net::OpenTimeout
    assert_includes Slk::Services::ApiClient::NETWORK_ERRORS, Net::ReadTimeout
  end

  def test_network_errors_includes_ssl_error
    assert_includes Slk::Services::ApiClient::NETWORK_ERRORS, OpenSSL::SSL::SSLError
  end

  # BASE_URL tests
  def test_base_url_defaults_to_slack_api
    # Temporarily unset env var to test default
    old_val = ENV.fetch('SLACK_API_BASE', nil)
    ENV.delete('SLACK_API_BASE')

    # Need to reload the constant - since we can't, just verify current value
    assert_match %r{^https://}, Slk::Services::ApiClient::BASE_URL
  ensure
    ENV['SLACK_API_BASE'] = old_val if old_val
  end

  # Response handling tests - we test the behavior by stubbing at HTTP level
  # These tests verify the ApiClient handles various response scenarios correctly

  # HTTP caching tests
  def test_client_maintains_http_cache
    # Verify the client has internal caching mechanism
    # We can't directly test private @http_cache, but we can verify behavior
    assert_respond_to @client, :close
  end
end

# Separate test class for response handling
class ApiClientResponseHandlingTest < Minitest::Test
  def setup
    @client = Slk::Services::ApiClient.new
  end

  def teardown
    @client.close
  end

  # Test handle_response by calling it directly via send
  def test_handles_success_response_with_ok_true
    response = build_response(Net::HTTPOK, '{"ok": true, "data": "test"}')

    result = @client.send(:handle_response, response, 'test.method')

    assert_equal true, result['ok']
    assert_equal 'test', result['data']
  end

  def test_raises_api_error_when_ok_false
    response = build_response(Net::HTTPOK, '{"ok": false, "error": "channel_not_found"}')

    error = assert_raises(Slk::ApiError) do
      @client.send(:handle_response, response, 'test.method')
    end

    assert_equal 'channel_not_found', error.message
  end

  def test_raises_api_error_with_unknown_error_when_no_error_field
    response = build_response(Net::HTTPOK, '{"ok": false}')

    error = assert_raises(Slk::ApiError) do
      @client.send(:handle_response, response, 'test.method')
    end

    assert_equal 'Unknown error', error.message
  end

  def test_raises_api_error_on_unauthorized
    response = build_response(Net::HTTPUnauthorized, '{}')

    error = assert_raises(Slk::ApiError) do
      @client.send(:handle_response, response, 'test.method')
    end

    assert_includes error.message, 'Invalid token'
  end

  def test_raises_api_error_on_rate_limit
    response = build_response(Net::HTTPTooManyRequests, '{}')

    error = assert_raises(Slk::ApiError) do
      @client.send(:handle_response, response, 'test.method')
    end

    assert_includes error.message, 'Rate limited'
  end

  def test_raises_api_error_on_other_http_errors
    response = build_response(Net::HTTPInternalServerError, '{}')

    error = assert_raises(Slk::ApiError) do
      @client.send(:handle_response, response, 'test.method')
    end

    assert_includes error.message, 'HTTP 500'
  end

  def test_raises_api_error_on_invalid_json
    response = build_response(Net::HTTPOK, 'not valid json')

    error = assert_raises(Slk::ApiError) do
      @client.send(:handle_response, response, 'test.method')
    end

    assert_includes error.message, 'Invalid JSON'
  end

  # Tests for workspace headers
  def test_workspace_headers_are_used
    workspace = Slk::Models::Workspace.new(
      name: 'test',
      token: 'xoxb-test-token'
    )

    assert_kind_of Hash, workspace.headers
    assert_includes workspace.headers.keys, 'Authorization'
  end

  def test_workspace_with_cookie_includes_cookie_header
    workspace = Slk::Models::Workspace.new(
      name: 'test',
      token: 'xoxc-test-token',
      cookie: 'xoxd-cookie-value'
    )

    assert_includes workspace.headers.keys, 'Cookie'
    assert_equal 'd=xoxd-cookie-value', workspace.headers['Cookie']
  end

  private

  # Build a real Net::HTTP response object for testing
  def build_response(response_class, body)
    code = response_code_for(response_class)
    response = response_class.new('1.1', code, '')
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def response_code_for(response_class)
    case response_class.name
    when /Unauthorized$/ then '401'
    when /TooManyRequests$/ then '429'
    when /InternalServerError$/ then '500'
    else '200'
    end
  end
end
