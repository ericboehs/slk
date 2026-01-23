# frozen_string_literal: true

require_relative '../test_helper'

class SearchApiTest < Minitest::Test
  def setup
    @api_client = MockApiClient.new
    @workspace = mock_workspace('test-workspace', 'xoxb-test-token')
    @search_api = Slk::Api::Search.new(@api_client, @workspace)
  end

  def test_messages_calls_search_messages_endpoint
    @api_client.stub('search.messages', { 'ok' => true, 'messages' => { 'matches' => [] } })

    @search_api.messages(query: 'test query')

    assert_equal 1, @api_client.calls.length
    call = @api_client.calls.first
    assert_equal 'search.messages', call[:method]
    assert_equal 'test query', call[:params][:query]
  end

  def test_messages_uses_default_count
    @api_client.stub('search.messages', { 'ok' => true })

    @search_api.messages(query: 'test')

    call = @api_client.calls.first
    assert_equal 20, call[:params][:count]
  end

  def test_messages_with_custom_count
    @api_client.stub('search.messages', { 'ok' => true })

    @search_api.messages(query: 'test', count: 50)

    call = @api_client.calls.first
    assert_equal 50, call[:params][:count]
  end

  def test_messages_with_pagination
    @api_client.stub('search.messages', { 'ok' => true })

    @search_api.messages(query: 'test', page: 3)

    call = @api_client.calls.first
    assert_equal 3, call[:params][:page]
  end

  def test_messages_caps_count_at_one_hundred
    @api_client.stub('search.messages', { 'ok' => true })

    @search_api.messages(query: 'test', count: 200)

    call = @api_client.calls.first
    assert_equal 100, call[:params][:count]
  end

  def test_messages_default_sort_options
    @api_client.stub('search.messages', { 'ok' => true })

    @search_api.messages(query: 'test')

    call = @api_client.calls.first
    assert_equal 'timestamp', call[:params][:sort]
    assert_equal 'desc', call[:params][:sort_dir]
  end
end
