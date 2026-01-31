# frozen_string_literal: true

require 'test_helper'

class MessageResolverTest < Minitest::Test
  # Mock Conversations API for testing
  class MockConversationsApi
    attr_reader :calls

    def initialize
      @calls = []
      @responses = []
    end

    def expect_history(response)
      @responses << response
    end

    def history(channel:, limit:, oldest:, latest:)
      @calls << { channel: channel, limit: limit, oldest: oldest, latest: latest }
      @responses.shift || { 'ok' => false }
    end
  end

  def setup
    @api = MockConversationsApi.new
    @debug_messages = []
    @resolver = Slk::Services::MessageResolver.new(
      conversations_api: @api,
      on_debug: ->(msg) { @debug_messages << msg }
    )
  end

  def test_fetch_by_ts_returns_matching_message
    message_ts = '1234567890.123456'
    expected_message = { 'ts' => message_ts, 'text' => 'Hello world' }

    @api.expect_history({
                          'ok' => true,
                          'messages' => [
                            { 'ts' => '1234567889.000000', 'text' => 'Earlier message' },
                            expected_message,
                            { 'ts' => '1234567891.000000', 'text' => 'Later message' }
                          ]
                        })

    result = @resolver.fetch_by_ts('C123', message_ts)

    assert_equal expected_message, result
    assert_equal 1, @api.calls.length
    assert_equal 'C123', @api.calls[0][:channel]
  end

  def test_fetch_by_ts_returns_nil_when_not_found
    @api.expect_history({
                          'ok' => true,
                          'messages' => [
                            { 'ts' => '1234567889.000000', 'text' => 'Different message' }
                          ]
                        })

    result = @resolver.fetch_by_ts('C123', '1234567890.123456')

    assert_nil result
  end

  def test_fetch_by_ts_returns_nil_when_api_fails
    @api.expect_history({ 'ok' => false, 'error' => 'channel_not_found' })

    result = @resolver.fetch_by_ts('C123', '1234567890.123456')

    assert_nil result
  end

  def test_fetch_by_ts_returns_nil_when_messages_empty
    @api.expect_history({ 'ok' => true, 'messages' => [] })

    result = @resolver.fetch_by_ts('C123', '1234567890.123456')

    assert_nil result
  end

  def test_fetch_by_ts_returns_nil_when_messages_missing
    @api.expect_history({ 'ok' => true })

    result = @resolver.fetch_by_ts('C123', '1234567890.123456')

    assert_nil result
  end

  def test_fetch_by_ts_uses_time_window_around_timestamp
    message_ts = '1234567890.000000'
    @api.expect_history({ 'ok' => true, 'messages' => [] })

    @resolver.fetch_by_ts('C123', message_ts)

    call = @api.calls[0]
    assert_equal '1234567889.0', call[:oldest]
    assert_equal '1234567891.0', call[:latest]
    assert_equal 10, call[:limit]
  end

  def test_fetch_by_ts_handles_api_error_gracefully
    # Create an API that raises an error
    error_api = Object.new
    def error_api.history(*)
      raise Slk::ApiError, 'Network error'
    end

    resolver = Slk::Services::MessageResolver.new(
      conversations_api: error_api,
      on_debug: ->(msg) { @debug_messages << msg }
    )

    result = resolver.fetch_by_ts('C123', '1234567890.123456')

    assert_nil result
  end

  def test_fetch_by_ts_calls_debug_on_api_error
    error_api = Object.new
    def error_api.history(*)
      raise Slk::ApiError, 'Network error'
    end

    debug_messages = []
    resolver = Slk::Services::MessageResolver.new(
      conversations_api: error_api,
      on_debug: ->(msg) { debug_messages << msg }
    )

    resolver.fetch_by_ts('C123', '1234567890.123456')

    assert_equal 1, debug_messages.length
    assert_match(/Could not fetch message/, debug_messages[0])
    assert_match(/Network error/, debug_messages[0])
  end

  def test_fetch_by_ts_works_without_debug_callback
    resolver = Slk::Services::MessageResolver.new(conversations_api: @api)
    @api.expect_history({ 'ok' => true, 'messages' => [] })

    # Should not raise an error
    result = resolver.fetch_by_ts('C123', '1234567890.123456')
    assert_nil result
  end
end
