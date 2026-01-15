# frozen_string_literal: true

require 'test_helper'

class ConversationsApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::Conversations.new(@mock_client, @workspace)
  end

  def test_list_calls_api
    @mock_client.stub('conversations.list', {
                        'ok' => true,
                        'channels' => [
                          { 'id' => 'C123', 'name' => 'general' },
                          { 'id' => 'C456', 'name' => 'random' }
                        ]
                      })

    result = @api.list
    assert_equal 2, result['channels'].size

    call = @mock_client.calls.last
    assert_equal 'conversations.list', call[:method]
    assert_equal 1000, call[:params][:limit]
  end

  def test_list_with_cursor
    @mock_client.stub('conversations.list', { 'ok' => true, 'channels' => [] })

    @api.list(cursor: 'dXNlcl9pZDo0')

    call = @mock_client.calls.last
    assert_equal 'dXNlcl9pZDo0', call[:params][:cursor]
  end

  def test_history_calls_api
    @mock_client.stub('conversations.history', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1234.5678', 'text' => 'Hello' }
                        ]
                      })

    result = @api.history(channel: 'C123')
    assert_equal 1, result['messages'].size

    call = @mock_client.calls.last
    assert_equal 'conversations.history', call[:method]
    assert_equal 'C123', call[:params][:channel]
  end

  def test_history_with_oldest
    @mock_client.stub('conversations.history', { 'ok' => true, 'messages' => [] })

    @api.history(channel: 'C123', oldest: '1234567890.123456')

    call = @mock_client.calls.last
    assert_equal '1234567890.123456', call[:params][:oldest]
  end

  def test_history_with_limit
    @mock_client.stub('conversations.history', { 'ok' => true, 'messages' => [] })

    @api.history(channel: 'C123', limit: 50)

    call = @mock_client.calls.last
    assert_equal 50, call[:params][:limit]
  end

  def test_replies_calls_api
    @mock_client.stub('conversations.replies', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1234.0000', 'text' => 'Parent' },
                          { 'ts' => '1234.0001', 'text' => 'Reply 1' }
                        ]
                      })

    result = @api.replies(channel: 'C123', timestamp: '1234.0000')
    assert_equal 2, result['messages'].size

    call = @mock_client.calls.last
    assert_equal 'conversations.replies', call[:method]
    assert_equal 'C123', call[:params][:channel]
    assert_equal '1234.0000', call[:params][:ts]
  end

  def test_open_calls_api
    @mock_client.stub('conversations.open', {
                        'ok' => true,
                        'channel' => { 'id' => 'D123' }
                      })

    result = @api.open(users: 'U123')
    assert_equal 'D123', result['channel']['id']

    call = @mock_client.calls.last
    assert_equal 'conversations.open', call[:method]
    assert_equal 'U123', call[:params][:users]
  end

  def test_open_with_multiple_users
    @mock_client.stub('conversations.open', { 'ok' => true, 'channel' => { 'id' => 'G123' } })

    @api.open(users: %w[U123 U456 U789])

    call = @mock_client.calls.last
    assert_equal 'U123,U456,U789', call[:params][:users]
  end

  def test_mark_calls_api
    @mock_client.stub('conversations.mark', { 'ok' => true })

    @api.mark(channel: 'C123', timestamp: '1234.5678')

    call = @mock_client.calls.last
    assert_equal 'conversations.mark', call[:method]
    assert_equal 'C123', call[:params][:channel]
    assert_equal '1234.5678', call[:params][:ts]
  end

  def test_info_calls_api
    @mock_client.stub('conversations.info', {
                        'ok' => true,
                        'channel' => {
                          'id' => 'C123',
                          'name' => 'general',
                          'is_member' => true
                        }
                      })

    result = @api.info(channel: 'C123')
    assert_equal 'general', result['channel']['name']

    call = @mock_client.calls.last
    assert_equal 'conversations.info', call[:method]
  end

  def test_members_calls_api
    @mock_client.stub('conversations.members', {
                        'ok' => true,
                        'members' => %w[U123 U456 U789]
                      })

    result = @api.members(channel: 'C123')
    assert_equal 3, result['members'].size

    call = @mock_client.calls.last
    assert_equal 'conversations.members', call[:method]
    assert_equal 'C123', call[:params][:channel]
  end
end
