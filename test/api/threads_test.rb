# frozen_string_literal: true

require 'test_helper'

class ThreadsApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::Threads.new(@mock_client, @workspace)
  end

  def test_get_view_calls_api
    @mock_client.stub('subscriptions.thread.getView', { 'ok' => true, 'threads' => [] })

    @api.get_view(limit: 5)

    call = @mock_client.calls.last
    assert_equal 'subscriptions.thread.getView', call[:method]
    assert_equal 5, call[:params][:limit]
  end

  def test_get_view_default_limit
    @mock_client.stub('subscriptions.thread.getView', { 'ok' => true })
    @api.get_view
    assert_equal 20, @mock_client.calls.last[:params][:limit]
  end

  def test_mark_calls_api
    @mock_client.stub('subscriptions.thread.mark', { 'ok' => true })

    @api.mark(channel: 'C1', thread_ts: '1.0', timestamp: '2.0')

    call = @mock_client.calls.last
    assert_equal 'subscriptions.thread.mark', call[:method]
    assert_equal 'C1', call[:params][:channel]
    assert_equal '1.0', call[:params][:thread_ts]
    assert_equal '2.0', call[:params][:ts]
  end

  def test_unread_count_returns_count
    @mock_client.stub('subscriptions.thread.getView',
                      { 'ok' => true, 'total_unread_replies' => 7 })
    assert_equal 7, @api.unread_count
  end

  def test_unread_count_returns_zero_when_missing
    @mock_client.stub('subscriptions.thread.getView', { 'ok' => true })
    assert_equal 0, @api.unread_count
  end

  def test_unreads_predicate_true
    @mock_client.stub('subscriptions.thread.getView',
                      { 'ok' => true, 'total_unread_replies' => 1 })
    assert_predicate @api, :unreads?
  end

  def test_unreads_predicate_false
    @mock_client.stub('subscriptions.thread.getView',
                      { 'ok' => true, 'total_unread_replies' => 0 })
    refute_predicate @api, :unreads?
  end
end
