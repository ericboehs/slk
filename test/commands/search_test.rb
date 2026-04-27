# frozen_string_literal: true

require_relative '../test_helper'

class SearchCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
  end

  def test_missing_query_shows_error
    command = build_command([])

    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Usage: slk search'
  end

  def test_execute_with_valid_query
    stub_search_response([
                           { 'ts' => '1234.0001', 'user' => 'U123', 'username' => 'john', 'text' => 'Hello deployment' }
                         ])

    command = build_command(['deployment'])
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Hello deployment'
  end

  def test_execute_with_in_channel_filter
    stub_search_response([])

    command = build_command(['error', '--in', '#engineering'])
    command.execute

    # Verify the query was built correctly
    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    assert call
    assert_includes call[:params][:query], 'in:#engineering'
  end

  def test_execute_with_from_user_filter
    stub_search_response([])

    command = build_command(['bug', '--from', '@john'])
    command.execute

    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    assert call
    assert_includes call[:params][:query], 'from:@john'
  end

  def test_execute_with_date_filters
    stub_search_response([])

    command = build_command(['meeting', '--after', '2024-01-01', '--before', '2024-12-31'])
    command.execute

    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    assert call
    assert_includes call[:params][:query], 'after:2024-01-01'
    assert_includes call[:params][:query], 'before:2024-12-31'
  end

  def test_execute_with_on_date_filter
    stub_search_response([])

    command = build_command(['standup', '--on', '2024-06-15'])
    command.execute

    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    assert call
    assert_includes call[:params][:query], 'on:2024-06-15'
  end

  def test_build_query_combines_all_filters
    stub_search_response([])

    command = build_command([
                              'deployment',
                              '--in', '#engineering',
                              '--from', '@alice',
                              '--after', '2024-01-01'
                            ])
    command.execute

    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    query = call[:params][:query]

    assert_includes query, 'deployment'
    assert_includes query, 'in:#engineering'
    assert_includes query, 'from:@alice'
    assert_includes query, 'after:2024-01-01'
  end

  def test_limit_option
    stub_search_response([])

    command = build_command(['test', '-n', '50'])
    command.execute

    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    assert_equal 50, call[:params][:count]
  end

  def test_page_option
    stub_search_response([])

    command = build_command(['test', '--page', '3'])
    command.execute

    call = @mock_client.calls.find { |c| c[:method] == 'search.messages' }
    assert_equal 3, call[:params][:page]
  end

  def test_json_output_format
    stub_search_response([
                           { 'ts' => '1234.0001', 'user' => 'U123', 'username' => 'john', 'text' => 'Test message' }
                         ])

    command = build_command(['test', '--json'])
    result = command.execute

    assert_equal 0, result
    output = JSON.parse(@io.string)
    assert output['results']
    assert output['pagination']
  end

  def test_handle_api_error_for_invalid_token_type
    @mock_client.stub('search.messages', {
                        'ok' => false,
                        'error' => 'not_allowed_token_type'
                      })

    # Make the mock client raise ApiError
    def @mock_client.get(workspace, method, params = {})
      @calls << { workspace: workspace.name, method: method, params: params }
      response = @responses[method] || { 'ok' => true }
      raise Slk::ApiError, response['error'] unless response['ok']

      response
    end

    command = build_command(['test'])
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'user token'
    assert_includes @err.string, 'xoxc/xoxs'
  end

  def test_no_results_shows_message
    stub_search_response([])

    command = build_command(['nonexistent'])
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No results found'
  end

  def test_missing_option_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--limit'])
    end

    assert_includes error.message, '--limit requires a value'
  end

  def test_missing_in_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--in'])
    end

    assert_includes error.message, '--in requires a value'
  end

  def test_missing_from_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--from'])
    end

    assert_includes error.message, '--from requires a value'
  end

  def test_missing_after_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--after'])
    end

    assert_includes error.message, '--after requires a value'
  end

  def test_missing_before_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--before'])
    end

    assert_includes error.message, '--before requires a value'
  end

  def test_missing_on_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--on'])
    end

    assert_includes error.message, '--on requires a value'
  end

  def test_missing_page_value_raises_error
    error = assert_raises(ArgumentError) do
      build_command(['test', '--page'])
    end

    assert_includes error.message, '--page requires a value'
  end

  def test_help_option
    command = build_command(['--help'])
    assert_equal 0, command.execute
    assert_includes @io.string, 'slk search'
    assert_includes @io.string, '--in'
    assert_includes @io.string, '--from'
  end

  def test_unknown_option_returns_error
    command = build_command(['test', '--bogus'])
    assert_equal 1, command.execute
    assert_includes @err.string, 'Unknown option'
  end

  def test_api_error_generic
    def @mock_client.get(workspace, method, params = {})
      @calls << { workspace: workspace.name, method: method, params: params }
      raise Slk::ApiError, 'server_down'
    end

    command = build_command(['test'])
    assert_equal 1, command.execute
    assert_includes @err.string, 'Search failed'
    assert_includes @err.string, 'server_down'
  end

  def test_threads_option_fetches_replies
    stub_search_response([thread_match])
    @mock_client.stub('conversations.replies', {
                        'ok' => true,
                        'messages' => [
                          { 'ts' => '1.0', 'user' => 'U1', 'text' => 'msg', 'thread_ts' => '1.0' },
                          { 'ts' => '1.1', 'user' => 'U2', 'text' => 'reply', 'thread_ts' => '1.0' }
                        ]
                      })

    command = build_command(['msg', '--threads'])
    assert_equal 0, command.execute
    assert_includes @io.string, 'reply'
  end

  def test_threads_option_handles_replies_error
    stub_search_response([thread_match])

    original_post_form = @mock_client.method(:post_form)
    @mock_client.define_singleton_method(:post_form) do |ws, m, params = {}|
      raise Slk::ApiError, 'replies_failed' if m == 'conversations.replies'

      original_post_form.call(ws, m, params)
    end

    command = build_command(['msg', '--threads'])
    assert_equal 0, command.execute
  end

  def thread_match
    { 'ts' => '1.0', 'user' => 'U1', 'text' => 'msg',
      'channel' => { 'id' => 'C1', 'name' => 'general' },
      'permalink' => 'https://x.slack.com/archives/C1/p1?thread_ts=1.0' }
  end

  def test_verbose_shows_pagination_info
    stub_search_response([])
    command = build_command(['test', '--verbose'])
    assert_equal 0, command.execute
  end

  private

  def stub_search_response(matches)
    @mock_client.stub('search.messages', {
                        'ok' => true,
                        'messages' => {
                          'matches' => matches.map { |m| build_match(m) },
                          'pagination' => { 'page' => 1, 'page_count' => 1, 'total_count' => matches.length }
                        }
                      })
  end

  def build_match(overrides = {})
    {
      'ts' => '1234567890.123456',
      'user' => 'U12345',
      'username' => 'testuser',
      'text' => 'Test message',
      'channel' => { 'id' => 'C12345', 'name' => 'general' },
      'permalink' => 'https://workspace.slack.com/archives/C12345/p1234567890123456'
    }.merge(overrides)
  end

  def build_command(args)
    runner = build_runner
    Slk::Commands::Search.new(args, runner: runner)
  end

  def build_runner
    token_store = Object.new
    workspace_list = [mock_workspace('test')]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end
    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store
    )
  end
end
