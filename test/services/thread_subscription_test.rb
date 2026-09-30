# frozen_string_literal: true

require 'test_helper'

class ThreadSubscriptionTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    workspace = mock_workspace('test')
    @service = Slk::Services::ThreadSubscription.new(
      conversations_api: Slk::Api::Conversations.new(@mock_client, workspace),
      threads_api: Slk::Api::Threads.new(@mock_client, workspace)
    )
  end

  def test_subscribe_marks_latest_reply_as_last_read
    stub_replies('1.0' => { 'ts' => '1.0', 'thread_ts' => '1.0', 'latest_reply' => '3.0' })

    result = @service.subscribe(channel_id: 'C1', timestamp: '1.0')

    assert_equal({ channel: 'C1', thread_ts: '1.0', last_read: '3.0' }, call_for('subscriptions.thread.add')[:params])
    assert_equal '1.0', result.thread_ts
    assert_equal '3.0', result.last_read
  end

  def test_unsubscribe_calls_thread_remove
    stub_replies('1.0' => { 'ts' => '1.0', 'thread_ts' => '1.0', 'latest_reply' => '3.0' })

    @service.unsubscribe(channel_id: 'C1', timestamp: '1.0')

    assert_equal({ channel: 'C1', thread_ts: '1.0', last_read: '3.0' },
                 call_for('subscriptions.thread.remove')[:params])
  end

  def test_parent_lookup_asks_for_a_single_message
    stub_replies('1.0' => { 'ts' => '1.0', 'thread_ts' => '1.0', 'latest_reply' => '3.0' })

    @service.subscribe(channel_id: 'C1', timestamp: '1.0')

    replies = call_for('conversations.replies')[:params]
    assert_equal '1.0', replies[:ts]
    assert_equal 1, replies[:limit]
  end

  def test_reply_timestamp_resolves_to_parent
    stub_replies(
      '2.0' => { 'ts' => '2.0', 'thread_ts' => '1.0' },
      '1.0' => { 'ts' => '1.0', 'thread_ts' => '1.0', 'latest_reply' => '5.0' }
    )

    result = @service.subscribe(channel_id: 'C1', timestamp: '2.0')

    assert_equal({ channel: 'C1', thread_ts: '1.0', last_read: '5.0' }, call_for('subscriptions.thread.add')[:params])
    assert_equal '1.0', result.thread_ts
  end

  def test_message_without_replies_uses_its_own_ts
    stub_replies('1.0' => { 'ts' => '1.0' })

    @service.subscribe(channel_id: 'C1', timestamp: '1.0')

    assert_equal({ channel: 'C1', thread_ts: '1.0', last_read: '1.0' }, call_for('subscriptions.thread.add')[:params])
  end

  def test_missing_message_raises_without_subscribing
    @mock_client.stub('conversations.replies', { 'ok' => true, 'messages' => [] })

    error = assert_raises(Slk::ApiError) { @service.subscribe(channel_id: 'C1', timestamp: '1.0') }

    assert_equal :thread_not_found, error.code
    assert_nil call_for('subscriptions.thread.add')
  end

  def test_api_error_propagates
    stub_replies('1.0' => { 'ts' => '1.0', 'thread_ts' => '1.0' })
    @mock_client.stub('subscriptions.thread.add',
                      Slk::ApiError.new('not_allowed_token_type', code: :not_allowed_token_type))

    error = assert_raises(Slk::ApiError) { @service.subscribe(channel_id: 'C1', timestamp: '1.0') }

    assert_equal :not_allowed_token_type, error.code
  end

  private

  def stub_replies(messages_by_ts)
    @mock_client.stub('conversations.replies', lambda { |params|
      { 'ok' => true, 'messages' => [messages_by_ts.fetch(params[:ts])] }
    })
  end

  def call_for(method)
    @mock_client.calls.find { |c| c[:method] == method }
  end
end
