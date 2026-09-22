# frozen_string_literal: true

require_relative '../test_helper'

class SentCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @client = SearchClient.new
    @workspaces = [mock_workspace('acme'), mock_workspace('dsva')]
    @client.response = lambda { |_workspace, _params|
      { 'messages' => { 'matches' => [], 'pagination' => { 'page_count' => 1 } } }
    }
  end

  def test_today_is_default_in_all_workspaces
    Date.stub(:today, Date.new(2026, 9, 22)) do
      assert_equal 0, command([]).execute
    end
    assert_equal(%w[acme dsva], @client.calls.map { |call| call[:workspace] })
    assert(@client.calls.all? { |call| call[:params][:query] == 'from:me on:2026-09-22' })
    assert(@client.calls.all? { |call| call[:params][:sort_dir] == 'asc' })
  end

  def test_yesterday_and_explicit_date
    Date.stub(:today, Date.new(2026, 9, 22)) { assert_equal 0, command(['yesterday']).execute }
    assert_equal 'from:me on:2026-09-21', @client.calls.first[:params][:query]
    @client.calls.clear
    assert_equal 0, command(['2026-09-19']).execute
    assert_equal 'from:me on:2026-09-19', @client.calls.first[:params][:query]
  end

  def test_since_includes_both_endpoints
    Date.stub(:today, Date.new(2026, 9, 22)) { assert_equal 0, command(['--since', '2026-09-15']).execute }
    assert_equal 'from:me after:2026-09-14 before:2026-09-23', @client.calls.first[:params][:query]
  end

  def test_workspace_option_searches_only_one_workspace
    assert_equal 0, command(['-w', 'dsva', '--json']).execute
    assert_equal(['dsva'], @client.calls.map { |call| call[:workspace] })
    assert_equal [], JSON.parse(@io.string)['results']
  end

  def test_timeline_sorted_across_workspaces_with_counts_and_json
    stub_matches({ 'acme' => [match('3.0', 'Final', 'C1', 'general'), match('1.0', 'First', 'C1', 'general')],
                   'dsva' => [match('2.0', 'Middle', 'D2', 'U2', is_im: true)] })
    assert_equal 0, command([]).execute
    text = @io.string
    assert_operator text.index('First'), :<, text.index('Middle')
    assert_operator text.index('Middle'), :<, text.index('Final')
    assert_includes text, '[acme] #general: 2'
    assert_includes text, '[acme] #general'
    assert_includes text, '[dsva]'

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['--json']).execute
    data = JSON.parse(@io.string)
    assert_equal(%w[First Middle Final], data['results'].map { |row| row['text'] })
    assert_equal(%w[acme dsva acme], data['results'].map { |row| row['workspace'] })
    assert_equal 2, data['counts'].find { |row| row['workspace'] == 'acme' }['count']
  end

  def test_collects_all_search_pages
    @client.response = lambda { |_workspace, params|
      page = params[:page]
      { 'messages' => { 'matches' => [
        { 'ts' => "#{page}.0", 'text' => "page#{page}", 'channel' => { 'id' => 'C1', 'name' => 'general' } }
      ], 'pagination' => { 'page_count' => 2, 'total_count' => 2 } } }
    }
    assert_equal 0, command(['-w', 'dsva', '--json']).execute
    assert_equal(%w[page1 page2], JSON.parse(@io.string)['results'].map { |row| row['text'] })
    assert_equal([1, 2], @client.calls.map { |call| call[:params][:page] })
  end

  def test_rejects_invalid_dates_and_conflicting_arguments_before_api
    [%w[2026-02-30], %w[yesterday --since 2026-01-01], %w[today yesterday], %w[garbage]].each do |args|
      assert_raises(Slk::UsageError) { command(args).execute }
    end
    assert_empty @client.calls
  end

  def test_all_and_workspace_cannot_be_combined
    assert_raises(Slk::UsageError) { command(['--all', '-w', 'dsva']).execute }
    assert_empty @client.calls
  end

  def test_api_failure_does_not_emit_partial_json
    @client.response = lambda { |workspace, _params|
      raise Slk::ApiError, 'ratelimited' if workspace.name == 'dsva'

      { 'messages' => { 'matches' => [match('1.0', 'Partial', 'C1', 'general')],
                        'pagination' => { 'page_count' => 1 } } }
    }
    assert_equal 1, command(['--json']).execute
    assert_empty @io.string
    assert_includes @err.string, 'ratelimited'
  end

  def test_since_future_date_is_rejected
    Date.stub(:today, Date.new(2026, 9, 22)) do
      assert_raises(Slk::UsageError) { command(['--since', '2026-09-23']).execute }
    end
    assert_empty @client.calls
  end

  def test_help_documents_caveats
    assert_equal 0, command(['--help']).execute
    assert_includes @io.string, 'profile timezone'
    assert_includes @io.string, '--since'
  end

  private

  def match(timestamp, text, id, name, is_im: false)
    { 'ts' => timestamp, 'text' => text, 'user' => 'U1', 'username' => 'me',
      'channel' => { 'id' => id, 'name' => name, 'is_im' => is_im } }
  end

  def stub_matches(by_workspace)
    @client.response = lambda { |workspace, _params|
      { 'messages' => { 'matches' => by_workspace.fetch(workspace.name, []),
                        'pagination' => { 'page_count' => 1 } } }
    }
  end

  class SearchClient < Slk::TestHelpers::MockApiClient
    attr_accessor :response

    def get(workspace, method, params = {})
      @calls << { workspace: workspace.name, method: method, params: params }
      @response.call(workspace, params)
    end
  end

  def command(args)
    list = @workspaces
    token_store = Object.new
    token_store.define_singleton_method(:workspace) { |name| list.find { |ws| ws.name == name } }
    token_store.define_singleton_method(:all_workspaces) { list }
    token_store.define_singleton_method(:on_warning=) { |_| nil }
    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'acme' }
    config.define_singleton_method(:on_warning=) { |_| nil }
    presets = Object.new
    presets.define_singleton_method(:on_warning=) { |_| nil }
    runner = Slk::Runner.new(output: @output, api_client: @client, token_store: token_store,
                             config: config, preset_store: presets)
    Slk::Commands::Sent.new(args, runner: runner)
  end
end
