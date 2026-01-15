# frozen_string_literal: true

require 'test_helper'

class ActivityApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::Activity.new(@mock_client, @workspace)
  end

  def test_feed_calls_api
    @mock_client.stub('activity.feed', {
                        'ok' => true,
                        'items' => [
                          {
                            'feed_ts' => '1767996268.000000',
                            'item' => {
                              'type' => 'message_reaction',
                              'reaction' => { 'user' => 'U123', 'name' => 'thumbsup' },
                              'message' => { 'ts' => '1767996106.296789', 'channel' => 'C123' }
                            }
                          }
                        ]
                      })

    result = @api.feed
    assert_equal 1, result['items'].size

    call = @mock_client.calls.last
    assert_equal 'activity.feed', call[:method]
    assert_equal 'priority_reads_and_unreads_v1', call[:params][:mode]
  end

  def test_feed_with_limit
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })

    @api.feed(limit: 50)

    call = @mock_client.calls.last
    assert_equal '50', call[:params][:limit]
  end

  def test_feed_with_custom_types
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })

    @api.feed(types: 'at_user,at_channel')

    call = @mock_client.calls.last
    assert_equal 'at_user,at_channel', call[:params][:types]
  end

  def test_feed_with_cursor
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })

    @api.feed(cursor: 'dXNlcl9pZDo0')

    call = @mock_client.calls.last
    assert_equal 'dXNlcl9pZDo0', call[:params][:cursor]
  end

  def test_feed_includes_required_params
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })

    @api.feed

    call = @mock_client.calls.last
    assert_equal 'false', call[:params][:archive_only]
    assert_equal 'false', call[:params][:snooze_only]
    assert_equal 'false', call[:params][:unread_only]
    assert_equal 'false', call[:params][:priority_only]
    assert_equal 'false', call[:params][:is_activity_inbox]
  end

  def test_feed_does_not_include_token_in_params
    # Token should be in Authorization header, not form params
    @mock_client.stub('activity.feed', { 'ok' => true, 'items' => [] })

    @api.feed

    call = @mock_client.calls.last
    refute call[:params].key?(:token), 'Token should not be in form params'
  end
end
