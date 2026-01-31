# frozen_string_literal: true

require 'test_helper'

class SavedApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::Saved.new(@mock_client, @workspace)
  end

  def test_list_calls_api
    @mock_client.stub('saved.list', {
                        'ok' => true,
                        'saved_items' => [
                          {
                            'item_id' => 'C123',
                            'item_type' => 'message',
                            'ts' => '1234567890.123456',
                            'state' => 'saved'
                          }
                        ]
                      })

    result = @api.list
    assert_equal 1, result['saved_items'].size

    call = @mock_client.calls.last
    assert_equal 'saved.list', call[:method]
  end

  def test_list_defaults_filter_to_saved
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list

    call = @mock_client.calls.last
    assert_equal 'saved', call[:params][:filter]
  end

  def test_list_with_custom_filter
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list(filter: 'completed')

    call = @mock_client.calls.last
    assert_equal 'completed', call[:params][:filter]
  end

  def test_list_with_in_progress_filter
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list(filter: 'in_progress')

    call = @mock_client.calls.last
    assert_equal 'in_progress', call[:params][:filter]
  end

  def test_list_defaults_limit_to_15
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list

    call = @mock_client.calls.last
    assert_equal '15', call[:params][:limit]
  end

  def test_list_with_custom_limit
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list(limit: 50)

    call = @mock_client.calls.last
    assert_equal '50', call[:params][:limit]
  end

  def test_list_with_cursor
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list(cursor: 'dXNlcl9pZDo0')

    call = @mock_client.calls.last
    assert_equal 'dXNlcl9pZDo0', call[:params][:cursor]
  end

  def test_list_without_cursor_does_not_include_param
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list

    call = @mock_client.calls.last
    refute call[:params].key?(:cursor)
  end

  def test_list_does_not_include_token_in_params
    @mock_client.stub('saved.list', { 'ok' => true, 'saved_items' => [] })

    @api.list

    call = @mock_client.calls.last
    refute call[:params].key?(:token), 'Token should not be in form params'
  end
end
