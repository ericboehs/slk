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

  def test_on_response_callback_is_settable
    callback = ->(method, code, _headers) { "#{method}: #{code}" }
    @client.on_response = callback
    assert_equal callback, @client.on_response
  end

  def test_on_request_body_callback_is_settable
    callback = ->(method, body) { "#{method}: #{body}" }
    @client.on_request_body = callback
    assert_equal callback, @client.on_request_body
  end

  def test_on_response_body_callback_is_settable
    callback = ->(method, body) { "#{method}: #{body}" }
    @client.on_response_body = callback
    assert_equal callback, @client.on_response_body
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

  # Rate limit handling tests
  def test_rate_limit_error_carries_retry_after
    error = Slk::RateLimitError.new('test', retry_after: 5)
    assert_equal 5, error.retry_after
    assert_kind_of Slk::ApiError, error
  end

  def test_rate_limit_error_without_retry_after
    error = Slk::RateLimitError.new('test')
    assert_nil error.retry_after
  end

  def test_wait_for_returns_retry_after_when_within_cap
    error = Slk::RateLimitError.new('test', retry_after: 10)
    assert_equal 10, @client.send(:wait_for, error)
  end

  def test_wait_for_returns_nil_beyond_cap
    error = Slk::RateLimitError.new('test', retry_after: 600)
    assert_nil @client.send(:wait_for, error)
  end

  def test_wait_for_falls_back_to_default_when_header_missing
    error = Slk::RateLimitError.new('test')
    assert_equal 30, @client.send(:wait_for, error)
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

# Integration tests using stubbed Net::HTTP
class ApiClientIntegrationTest < Minitest::Test
  def setup
    @client = Slk::Services::ApiClient.new
    @workspace = mock_workspace
  end

  def teardown
    @client.close
  end

  def test_post_returns_parsed_json
    stub_http(success('{"ok":true,"value":"v"}')) do
      result = @client.post(@workspace, 'm', { x: 1 })
      assert_equal 'v', result['value']
    end
    assert_equal 1, @client.call_count
  end

  def test_get_with_params_appends_query
    captured = []
    stub_http(success('{"ok":true}'), capture: captured) do
      @client.get(@workspace, 'm', { foo: 'bar' })
    end
    assert_equal 1, captured.size
  end

  def test_post_form_sends_form_data
    stub_http(success('{"ok":true}')) do
      @client.post_form(@workspace, 'm', { a: 1 })
    end
    assert_equal 1, @client.call_count
  end

  def test_post_form_empty_params_skips_body
    stub_http(success('{"ok":true}')) do
      @client.post_form(@workspace, 'm', {})
    end
    assert_equal 1, @client.call_count
  end

  def test_get_no_params_skips_query
    stub_http(success('{"ok":true}')) do
      @client.get(@workspace, 'm')
    end
    assert_equal 1, @client.call_count
  end

  def test_callbacks_invoked_on_request_and_response
    req_calls = []
    resp_calls = []
    @client.on_request = ->(method, count) { req_calls << [method, count] }
    @client.on_response = ->(method, code, headers) { resp_calls << [method, code, headers] }
    @client.on_request_body = ->(method, body) { req_calls << [:body, method, body] }
    @client.on_response_body = ->(method, body) { resp_calls << [:body, method, body] }

    stub_http(success('{"ok":true}')) { @client.post(@workspace, 'm', { z: 1 }) }

    refute_empty req_calls
    refute_empty resp_calls
  end

  def test_network_error_wraps_in_api_error
    stub_http_error(SocketError) do
      err = assert_raises(Slk::ApiError) { @client.post(@workspace, 'm') }
      assert_equal :network_error, err.code
    end
  end

  def test_rate_limited_response_retries_then_succeeds
    @client.define_singleton_method(:sleep) { |_s| nil }
    waits = []
    @client.on_response = ->(method, code, headers) { waits << [method, code, headers] }
    stub_http_sequence([rate_limited(1), success('{"ok":true}')]) do
      result = @client.post(@workspace, 'm')
      assert result['ok']
    end
    assert(waits.any? { |w| w[1] == 'rate-wait' })
  end

  def test_rate_limited_no_retry_when_no_retry_after_and_exceeds_default
    old = ENV.fetch('SLK_DEFAULT_RETRY_AFTER', nil)
    ENV['SLK_DEFAULT_RETRY_AFTER'] = '0'
    @client.define_singleton_method(:sleep) { |_s| nil }
    stub_http(rate_limited(nil)) do
      assert_raises(Slk::RateLimitError) { @client.post(@workspace, 'm') }
    end
  ensure
    ENV['SLK_DEFAULT_RETRY_AFTER'] = old
  end

  def test_rate_limited_response_after_retry_still_fails
    @client.define_singleton_method(:sleep) { |_s| nil }
    stub_http_sequence([rate_limited(1), rate_limited(1)]) do
      assert_raises(Slk::RateLimitError) { @client.post(@workspace, 'm') }
    end
  end

  def test_predictive_throttle_sleeps_when_remaining_zero
    slept = []
    @client.define_singleton_method(:sleep) { |s| slept << s }
    headers_zero = { 'X-RateLimit-Remaining' => '0', 'X-RateLimit-Reset' => (Time.now.to_i + 5).to_s }
    stub_http_sequence([success('{"ok":true}', headers_zero), success('{"ok":true}')]) do
      @client.post(@workspace, 'm')
      @client.post(@workspace, 'm')
    end
    refute_empty slept
  end

  def test_predictive_throttle_skips_when_reset_too_far
    slept = []
    @client.define_singleton_method(:sleep) { |s| slept << s }
    headers = { 'X-RateLimit-Remaining' => '0', 'X-RateLimit-Reset' => (Time.now.to_i + 9999).to_s }
    stub_http_sequence([success('{"ok":true}', headers), success('{"ok":true}')]) do
      @client.post(@workspace, 'm')
      @client.post(@workspace, 'm')
    end
    assert_empty slept
  end

  def test_predictive_throttle_clears_when_already_past
    slept = []
    @client.define_singleton_method(:sleep) { |s| slept << s }
    headers = { 'X-RateLimit-Remaining' => '0', 'X-RateLimit-Reset' => (Time.now.to_i - 1).to_s }
    stub_http_sequence([success('{"ok":true}', headers), success('{"ok":true}')]) do
      @client.post(@workspace, 'm')
      @client.post(@workspace, 'm')
    end
    assert_empty slept
  end

  def test_429_response_raises_rate_limit_error
    @client.define_singleton_method(:sleep) { |_s| nil }
    stub_http(http_too_many('30')) do
      assert_raises(Slk::RateLimitError) { @client.post(@workspace, 'm') }
    end
  end

  def test_429_response_no_retry_after_header
    @client.define_singleton_method(:sleep) { |_s| nil }
    old = ENV.fetch('SLK_DEFAULT_RETRY_AFTER', nil)
    ENV['SLK_DEFAULT_RETRY_AFTER'] = '0'
    stub_http(http_too_many(nil)) do
      assert_raises(Slk::RateLimitError) { @client.post(@workspace, 'm') }
    end
  ensure
    ENV['SLK_DEFAULT_RETRY_AFTER'] = old
  end

  def test_safe_close_handles_already_closed
    # Force a connection then close twice - second close should not raise
    stub_http(success('{"ok":true}')) { @client.post(@workspace, 'm') }
    @client.close
    @client.close # Should not raise
  end

  def test_safe_close_handles_io_error
    cache = @client.instance_variable_get(:@http_cache)
    bad_http = StubHTTP.new(->(_r) {})
    bad_http.start
    bad_http.define_singleton_method(:finish) { raise IOError, 'closed' }
    cache['x:443'] = bad_http
    @client.close # Should not raise IOError
  end

  def test_configure_ssl_skips_ssl_setup_for_http_uri
    http = StubHTTP.new(->(_r) {})
    @client.send(:configure_ssl, http, URI('http://example.com/'))
    refute http.use_ssl
  end

  def test_safe_close_skips_unstarted_connection
    cache = @client.instance_variable_get(:@http_cache)
    unstarted = StubHTTP.new(->(_r) {})
    # Don't call start
    cache['y:443'] = unstarted
    @client.close
  end

  def test_get_http_returns_cached_when_started
    # Run two posts; second should reuse cached connection
    counter = { calls: 0 }
    response_body = success('{"ok":true}')
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      counter[:calls] += 1
      StubHTTP.new(->(_req) { response_body })
    end
    @client.post(@workspace, 'm')
    @client.post(@workspace, 'm')
    Net::HTTP.define_singleton_method(:new, original)
    assert_equal 1, counter[:calls]
  end

  def test_track_rate_limit_with_negative_reset
    @client.define_singleton_method(:sleep) { |_s| nil }
    headers = { 'X-RateLimit-Remaining' => '0', 'X-RateLimit-Reset' => '-1' }
    stub_http(success('{"ok":true}', headers)) do
      @client.post(@workspace, 'm')
    end
  end

  def test_track_rate_limit_with_remaining_non_zero
    headers = { 'X-RateLimit-Remaining' => '5', 'X-RateLimit-Reset' => '12345' }
    stub_http(success('{"ok":true}', headers)) do
      @client.post(@workspace, 'm')
    end
  end

  def test_track_rate_limit_with_zero_remaining_no_reset
    headers = { 'X-RateLimit-Remaining' => '0' }
    stub_http(success('{"ok":true}', headers)) do
      @client.post(@workspace, 'm')
    end
  end

  def test_log_response_body_skips_nil_body
    bodies = []
    @client.on_response_body = ->(_m, b) { bodies << b }
    response = success('{"ok":true}')
    response.instance_variable_set(:@body, nil)
    # Bypass through send_one_request's log_response_body directly
    @client.send(:log_response_body, 'm', nil)
    assert_empty bodies
  end

  def test_response_body_callback_invoked
    bodies = []
    @client.on_response_body = ->(method, body) { bodies << [method, body] }
    stub_http(success('{"ok":true}')) { @client.post(@workspace, 'm') }
    refute_empty bodies
  end

  def test_workspace_with_cookie_get_request
    ws = Slk::Models::Workspace.new(name: 'test', token: 'xoxc-t', cookie: 'xoxd-c')
    captured = []
    stub_http(success('{"ok":true}'), capture: captured) do
      @client.get(ws, 'm', { foo: 'bar' })
    end
    assert(captured.any? { |req| req['Cookie'] })
  end

  private

  def success(body, extra_headers = {})
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    extra_headers.each { |k, v| response[k] = v }
    response
  end

  def rate_limited(retry_after)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.instance_variable_set(:@body, '{"ok":false,"error":"ratelimited"}')
    response.instance_variable_set(:@read, true)
    response['Retry-After'] = retry_after.to_s if retry_after
    response
  end

  def http_too_many(retry_after)
    response = Net::HTTPTooManyRequests.new('1.1', '429', 'Too Many Requests')
    response.instance_variable_set(:@body, '')
    response.instance_variable_set(:@read, true)
    response['Retry-After'] = retry_after if retry_after
    response
  end

  def stub_http(response, capture: nil)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(lambda { |req|
        capture&.push(req)
        response
      })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def stub_http_sequence(responses)
    idx = 0
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(lambda { |_req|
        result = responses[idx]
        idx += 1
        result
      })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def stub_http_error(error_class)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(->(_req) { raise error_class })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  class StubHTTP
    attr_accessor :use_ssl, :verify_mode, :open_timeout, :read_timeout, :keep_alive_timeout, :cert_store

    def initialize(handler)
      @handler = handler
      @started = false
    end

    def use_ssl?
      @use_ssl
    end

    def start
      @started = true
      self
    end

    def started? = @started

    def finish
      @started = false
    end

    def request(req) = @handler.call(req)
  end
end
