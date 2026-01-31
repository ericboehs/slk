# frozen_string_literal: true

require 'test_helper'

class LaterCommandTest < Minitest::Test
  # Mock saved API
  class MockSavedApi
    attr_reader :calls

    def initialize
      @calls = []
      @responses = []
    end

    def expect_list(response)
      @responses << response
    end

    def list(filter:, limit:)
      @calls << { filter: filter, limit: limit }
      @responses.shift || { 'ok' => false }
    end
  end

  # Mock conversations API for message fetching
  class MockConversationsApi
    attr_reader :calls

    def initialize
      @calls = []
      @responses = {}
    end

    def stub_history(channel, response)
      @responses[channel] = response
    end

    def history(channel:, limit:, oldest:, latest:)
      @calls << { channel: channel, limit: limit, oldest: oldest, latest: latest }
      @responses[channel] || { 'ok' => true, 'messages' => [] }
    end
  end

  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @saved_api = MockSavedApi.new
    @conversations_api = MockConversationsApi.new
  end

  def test_execute_displays_saved_items
    @saved_api.expect_list({
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

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    result = command.execute

    assert_equal 0, result
  end

  def test_execute_with_no_items
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/No saved items found/, @io.string)
  end

  def test_execute_with_api_error
    @saved_api.expect_list({ 'ok' => false, 'error' => 'not_allowed' })

    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_match(/Failed to fetch saved items/, @err.string)
  end

  def test_execute_with_completed_filter
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--completed', '--no-content'], runner: runner)
    command.execute

    assert_equal 'completed', @saved_api.calls.first[:filter]
  end

  def test_execute_with_in_progress_filter
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--in-progress', '--no-content'], runner: runner)
    command.execute

    assert_equal 'in_progress', @saved_api.calls.first[:filter]
  end

  def test_execute_with_custom_limit
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['-n', '50', '--no-content'], runner: runner)
    command.execute

    assert_equal 50, @saved_api.calls.first[:limit]
  end

  def test_execute_with_counts_option
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message', 'state' => 'saved' },
                               { 'item_id' => 'C456', 'item_type' => 'message', 'state' => 'saved',
                                 'date_due' => Time.now.to_i - 3600 }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new(['--counts'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/Total: 2/, @io.string)
    assert_match(/Overdue: 1/, @io.string)
  end

  def test_execute_with_json_output
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               {
                                 'item_id' => 'C123',
                                 'item_type' => 'message',
                                 'ts' => '1234567890.123456',
                                 'state' => 'saved',
                                 'date_created' => 1_700_000_000
                               }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new(['--json', '--no-content'], runner: runner)
    result = command.execute

    assert_equal 0, result
    output = JSON.parse(@io.string)
    assert_kind_of Array, output
    assert_equal 1, output.size
    assert_equal 'C123', output[0]['channel_id']
    assert_equal 'saved', output[0]['state']
  end

  def test_help_option
    runner = build_runner
    command = Slk::Commands::Later.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/slk later/, @io.string)
    assert_match(/--limit/, @io.string)
    assert_match(/--completed/, @io.string)
    assert_match(/--counts/, @io.string)
    assert_match(/--no-content/, @io.string)
  end

  def test_default_limit_is_fifteen
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    command.execute

    assert_equal 15, @saved_api.calls.first[:limit]
  end

  def test_default_filter_is_saved
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    command.execute

    assert_equal 'saved', @saved_api.calls.first[:filter]
  end

  def test_execute_handles_api_exception
    runner = build_runner
    # Override saved_api to raise an exception
    error_api = Object.new
    error_api.define_singleton_method(:list) { |**_| raise Slk::ApiError, 'Network timeout' }
    runner.define_singleton_method(:saved_api) { |_| error_api }

    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_match(/Failed to fetch saved items.*Network timeout/, @err.string)
  end

  def test_no_wrap_option_sets_truncate_and_default_width
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-wrap', '--no-content'], runner: runner)

    assert_equal true, command.options[:truncate]
    assert_equal 140, command.options[:width]
  end

  def test_no_wrap_with_explicit_width
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-wrap', '--width', '80', '--no-content'], runner: runner)

    assert_equal true, command.options[:truncate]
    assert_equal 80, command.options[:width]
  end

  def test_execute_fetches_message_content_when_not_skipped
    @saved_api.expect_list({
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

    @conversations_api.stub_history('C123', {
                                      'ok' => true,
                                      'messages' => [
                                        { 'ts' => '1234567890.123456', 'text' => 'Test message', 'user' => 'U123' }
                                      ]
                                    })

    runner = build_runner_with_cache
    command = Slk::Commands::Later.new([], runner: runner) # No --no-content
    result = command.execute

    assert_equal 0, result
    assert_equal 1, @conversations_api.calls.length
    assert_equal 'C123', @conversations_api.calls.first[:channel]
  end

  def test_workspace_emoji_option_is_parsed
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--workspace-emoji', '--no-content'], runner: runner)

    assert_equal true, command.options[:workspace_emoji]
  end

  def test_execute_handles_items_without_ts
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message', 'state' => 'saved' }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    # Should not attempt to fetch message content when ts is missing
    assert_equal 0, @conversations_api.calls.length
  end

  def test_shows_fetch_failure_summary_when_content_fails
    @saved_api.expect_list({
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

    # Return empty messages so fetch_by_ts returns nil
    @conversations_api.stub_history('C123', { 'ok' => true, 'messages' => [] })

    runner = build_runner_with_cache
    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/Could not load content for 1 item/, @io.string)
  end

  private

  def build_runner
    saved_api = @saved_api
    conversations_api = @conversations_api

    token_store = Object.new
    workspace = Slk::Models::Workspace.new(name: 'test', token: 'xoxb-test')

    token_store.define_singleton_method(:workspace) { |_name = nil| workspace }
    token_store.define_singleton_method(:all_workspaces) { [workspace] }
    token_store.define_singleton_method(:workspace_names) { ['test'] }
    token_store.define_singleton_method(:empty?) { false }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:on_warning=) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }

    runner = Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: MockApiClient.new,
      cache_store: cache_store,
      preset_store: preset_store
    )

    # Override the API accessors to return our mocks
    runner.define_singleton_method(:saved_api) { |_workspace_name = nil| saved_api }
    runner.define_singleton_method(:conversations_api) { |_workspace_name = nil| conversations_api }

    runner
  end

  def build_runner_with_cache
    saved_api = @saved_api
    conversations_api = @conversations_api

    token_store = Object.new
    workspace = Slk::Models::Workspace.new(name: 'test', token: 'xoxb-test')

    token_store.define_singleton_method(:workspace) { |_name = nil| workspace }
    token_store.define_singleton_method(:all_workspaces) { [workspace] }
    token_store.define_singleton_method(:workspace_names) { ['test'] }
    token_store.define_singleton_method(:empty?) { false }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:on_warning=) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    # Cache store with user lookup support
    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }
    cache_store.define_singleton_method(:get_user) { |_workspace, _user_id| 'Test User' }
    cache_store.define_singleton_method(:set_user) { |_workspace, _user_id, _name| nil }

    runner = Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: MockApiClient.new,
      cache_store: cache_store,
      preset_store: preset_store
    )

    # Override the API accessors to return our mocks
    runner.define_singleton_method(:saved_api) { |_workspace_name = nil| saved_api }
    runner.define_singleton_method(:conversations_api) { |_workspace_name = nil| conversations_api }

    runner
  end
end
