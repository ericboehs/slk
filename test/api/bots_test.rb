# frozen_string_literal: true

require 'test_helper'

class BotsApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
  end

  def test_info_calls_api
    @mock_client.stub('bots.info', {
                        'ok' => true,
                        'bot' => {
                          'id' => 'B123',
                          'name' => 'TestBot',
                          'deleted' => false
                        }
                      })

    api = SlackCli::Api::Bots.new(@mock_client, @workspace)
    result = api.info('B123')

    assert_equal 'B123', result['id']
    assert_equal 'TestBot', result['name']

    call = @mock_client.calls.last
    assert_equal 'bots.info', call[:method]
  end

  def test_info_returns_nil_when_not_ok
    @mock_client.stub('bots.info', {
                        'ok' => false,
                        'error' => 'bot_not_found'
                      })

    api = SlackCli::Api::Bots.new(@mock_client, @workspace)
    result = api.info('B999')

    assert_nil result
  end

  def test_get_name_returns_bot_name
    @mock_client.stub('bots.info', {
                        'ok' => true,
                        'bot' => {
                          'id' => 'B123',
                          'name' => 'TestBot'
                        }
                      })

    api = SlackCli::Api::Bots.new(@mock_client, @workspace)
    name = api.get_name('B123')

    assert_equal 'TestBot', name
  end

  def test_get_name_returns_nil_when_bot_not_found
    @mock_client.stub('bots.info', {
                        'ok' => false,
                        'error' => 'bot_not_found'
                      })

    api = SlackCli::Api::Bots.new(@mock_client, @workspace)
    name = api.get_name('B999')

    assert_nil name
  end

  def test_info_returns_nil_on_api_error
    api_client = Object.new
    api_client.define_singleton_method(:post_form) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, 'network_error'
    end

    api = SlackCli::Api::Bots.new(api_client, @workspace)
    result = api.info('B123')

    assert_nil result
  end

  def test_on_debug_called_on_api_error
    debug_messages = []
    api_client = Object.new
    api_client.define_singleton_method(:post_form) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, 'bot_not_found'
    end

    api = SlackCli::Api::Bots.new(
      api_client,
      @workspace,
      on_debug: ->(msg) { debug_messages << msg }
    )
    api.info('BFAIL')

    assert_equal 1, debug_messages.size
    assert_match(/Bot lookup failed for BFAIL/, debug_messages.first)
    assert_match(/bot_not_found/, debug_messages.first)
  end
end
