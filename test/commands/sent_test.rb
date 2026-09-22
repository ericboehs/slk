# frozen_string_literal: true

require_relative '../test_helper'

class SentCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @client = SearchClient.new
    @paths = TempPaths.new('slk-sent-test')
    @cache_store = Slk::Services::CacheStore.new(paths: @paths)
    @workspaces = [mock_workspace('acme'), mock_workspace('dsva')]
    @client.response = lambda { |_workspace, _params|
      { 'messages' => { 'matches' => [], 'pagination' => { 'page_count' => 1 } } }
    }
  end

  def teardown
    FileUtils.remove_entry(@paths.dir)
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
    assert_equal 0, command(['-w', 'dsva', '--mine', '--json']).execute
    assert_equal(['dsva'], @client.calls.map { |call| call[:workspace] })
    assert_equal [], JSON.parse(@io.string)['results']
  end

  def test_timeline_sorted_across_workspaces_with_counts_and_json
    stub_matches({ 'acme' => [match('3.0', 'Final', 'C1', 'general'), match('1.0', 'First', 'C1', 'general')],
                   'dsva' => [match('2.0', 'Middle', 'D2', 'U2', is_im: true)] })
    assert_equal 0, command(['--mine']).execute
    text = @io.string
    assert_operator text.index('First'), :<, text.index('Middle')
    assert_operator text.index('Middle'), :<, text.index('Final')
    assert_includes text, '[acme] #general: 2'
    assert_includes text, '[acme] #general'
    assert_includes text, '[dsva]'

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['--mine', '--json']).execute
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
    assert_equal 0, command(['-w', 'dsva', '--mine', '--json']).execute
    assert_equal(%w[page1 page2], JSON.parse(@io.string)['results'].map { |row| row['text'] })
    assert_equal([1, 2], @client.calls.map { |call| call[:params][:page] })
  end

  def test_default_thread_fetches_all_replies_including_after_mine
    sent = match('2.0', 'my reply', 'C1', 'project').merge(
      'permalink' => 'https://slack.test/archives/C1/p2?thread_ts=1.0'
    )
    stub_matches('acme' => [sent])
    @client.stub('conversations.replies', lambda { |params|
      if params[:cursor]
        { 'messages' => [raw('3.0', 'U2', 'reply after me', thread_ts: '1.0')], 'has_more' => false }
      else
        { 'messages' => [raw('1.0', 'U2', 'parent'), raw('2.0', 'U1', 'my reply', thread_ts: '1.0')],
          'has_more' => true, 'response_metadata' => { 'next_cursor' => 'p2' } }
      end
    })
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    data = JSON.parse(@io.string)
    assert_equal 1, data['conversations'].size
    thread = data['conversations'].first
    assert_equal 'thread', thread['type']
    assert_equal '1.0', thread['thread_ts']
    assert_equal(%w[1.0 2.0 3.0], thread['messages'].map { |message| message['ts'] })
    assert_equal([false, true, false], thread['messages'].map { |message| message['mine'] })
    assert_equal false, thread['last_speaker_is_me']
    assert_equal(2, @client.calls.count { |call| call[:method] == 'conversations.replies' })
  end

  def test_dm_fetches_full_paged_day_and_caps_only_output_not_signal
    stub_matches('dsva' => [match('12.0', 'my DM', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', lambda { |params|
      if params[:cursor]
        { 'messages' => [raw('11.0', 'U2', 'before mine')], 'has_more' => false }
      else
        { 'messages' => [raw('13.0', 'U2', 'after mine'), raw('12.0', 'U1', 'my DM')],
          'has_more' => true, 'response_metadata' => { 'next_cursor' => 'p2' } }
      end
    })
    assert_equal 0, command(['-w', 'dsva', '--json', '--max', '2']).execute
    data = JSON.parse(@io.string)
    assert_equal 1, data['conversations'].size
    conversation = data['conversations'].first
    assert_equal 'im', conversation['type']
    assert_equal(%w[12.0 13.0], conversation['messages'].map { |message| message['ts'] })
    assert_equal 1, conversation['dropped_messages']
    assert_equal false, conversation['last_speaker_is_me']
    assert_equal(2, @client.calls.count { |call| call[:method] == 'conversations.history' })
    params = @client.calls.find { |call| call[:method] == 'conversations.history' }[:params]
    assert params[:oldest]
    assert params[:latest]
  end

  def test_channel_merges_overlapping_windows_and_includes_replies_to_own_post
    stub_matches('acme' => [match('100.0', 'post A', 'C1', 'project').merge('reply_count' => 1),
                               match('200.0', 'post B', 'C1', 'project')])
    @client.stub('conversations.history', lambda { |params|
      if params[:oldest]
        { 'messages' => [raw('300.0', 'U2', 'someone else'), raw('200.0', 'U1', 'post B'),
                         raw('100.0', 'U1', 'post A', reply_count: 1)] }
      else
        { 'messages' => [raw('99.0', 'U2', 'earlier')] }
      end
    })
    @client.stub('conversations.replies', {
                   'messages' => [raw('100.0', 'U1', 'post A'), raw('400.0', 'U2', 'thread answer', thread_ts: '100.0')]
                 })
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    conversations = JSON.parse(@io.string)['conversations']
    assert_equal 1, conversations.size
    conversation = conversations.first
    assert_equal 'channel', conversation['type']
    assert_equal(%w[99.0 100.0 200.0 300.0 400.0], conversation['messages'].map { |message| message['ts'] })
    assert_equal false, conversation['last_speaker_is_me']
    assert_equal(2, @client.calls.count { |call| call[:method] == 'conversations.history' })
    assert_equal(1, @client.calls.count { |call| call[:method] == 'conversations.replies' })
  end

  def test_old_own_post_in_preceding_window_does_not_expand_its_thread
    stub_matches('acme' => [match('200.0', 'mine', 'C1', 'project')])
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => params[:oldest] ? [] : [raw('100.0', 'U1', 'old', reply_count: 2)] }
    })
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    assert_equal(0, @client.calls.count { |call| call[:method] == 'conversations.replies' })
  end

  def test_own_thread_parent_sets_conversation_order
    parent = match('1.0', 'my parent', 'C1', 'project')
    reply = match('2.0', 'my reply', 'C1', 'project').merge(
      'permalink' => 'https://slack.test/archives/C1/p2?thread_ts=1.0'
    )
    other = match('1.5', 'different channel', 'C2', 'other')
    stub_matches('acme' => [parent, other, reply])
    @client.stub('conversations.replies', {
                   'messages' => [raw('1.0', 'U1', 'my parent'), raw('2.0', 'U1', 'my reply', thread_ts: '1.0')]
                 })
    @client.stub('conversations.history', { 'messages' => [] })
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    conversations = JSON.parse(@io.string)['conversations']
    assert_equal(%w[thread channel], conversations.map { |group| group['type'] })
    assert_equal(%w[1.0 2.0], conversations.first['messages'].map { |message| message['ts'] })
  end

  def test_thread_parent_is_not_repeated_in_channel_window
    threaded_hit = match('2.0', 'mine in thread', 'C1', 'project').merge(
      'permalink' => 'https://slack.test/archives/C1/p2?thread_ts=1.0'
    )
    stub_matches('acme' => [threaded_hit, match('3.0', 'other post', 'C1', 'project')])
    @client.stub('conversations.replies', {
                   'messages' => [raw('1.0', 'U2', 'parent'), raw('2.0', 'U1', 'mine in thread', thread_ts: '1.0')]
                 })
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => params[:oldest] ? [raw('3.0', 'U1', 'other post')] : [raw('1.0', 'U2', 'parent')] }
    })
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    conversations = JSON.parse(@io.string)['conversations']
    assert_equal(%w[thread channel], conversations.map { |group| group['type'] })
    timestamps = conversations.flat_map do |group|
      group['messages'].map { |message| message['ts'] }
    end
    assert_equal %w[1.0 2.0 3.0], timestamps
  end

  def test_cursor_without_progress_is_an_error_not_truncated_json
    stub_matches('dsva' => [match('12.0', 'my DM', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', { 'messages' => [raw('12.0', 'U1', 'my DM')], 'has_more' => true })
    assert_equal 1, command(['-w', 'dsva', '--json']).execute
    assert_empty @io.string
    assert_includes @err.string, 'has_more without a new cursor'
  end

  def test_range_json_has_stable_shape
    Date.stub(:today, Date.new(2026, 9, 22)) do
      assert_equal 0, command(['--since', '2026-09-20', '--json']).execute
    end
    data = JSON.parse(@io.string)
    assert_nil data['date']
    assert_equal({ 'since' => '2026-09-20', 'through' => '2026-09-22' }, data['range'])
    assert_equal [], data['conversations']
  end

  def test_context_text_marks_own_messages_and_reply_signal
    stub_matches('acme' => [match('2.0', 'mine', 'C1', 'project')])
    @client.stub('conversations.history', { 'messages' => [raw('3.0', 'U2', 'their reply')] })
    assert_equal 0, command(['-w', 'acme', '--before', '0']).execute
    assert_includes @io.string, '[acme] #project'
    assert_includes @io.string, '▶'
    assert_includes @io.string, '↩ replied after you'
  end

  def test_zero_window_skips_history_and_still_includes_search_hit
    stub_matches('acme' => [match('2.0', 'mine', 'C1', 'project')])
    assert_equal 0, command(['-w', 'acme', '--before', '0', '--after-minutes', '0', '--json']).execute
    assert_equal(%w[2.0], JSON.parse(@io.string)['conversations'].first['messages'].map { |message| message['ts'] })
    refute(@client.calls.any? { |call| call[:method] == 'conversations.history' })
  end

  def test_missing_search_user_id_resolves_authenticated_sender
    stub_matches('acme' => [match('2.0', 'mine', 'C1', 'project').merge('user' => nil, 'username' => 'me')])
    @client.stub('auth.test', { 'user_id' => 'U1' })
    assert_equal 0, command(['-w', 'acme', '--before', '0', '--after-minutes', '0', '--json']).execute
    message = JSON.parse(@io.string)['conversations'].first['messages'].first
    assert_equal 'U1', message['user']
    assert_equal true, message['mine']
    assert_equal(1, @client.calls.count { |call| call[:method] == 'auth.test' })
  end

  def test_max_text_notes_dropped_messages_and_last_word
    stub_matches('dsva' => [match('12.0', 'my DM', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', {
                   'messages' => [raw('12.0', 'U1', 'my DM'), raw('11.0', 'U2', 'earlier reply'),
                                  raw('10.0', 'U2', 'earlier parent')]
                 })
    assert_equal 0, command(['-w', 'dsva', '--max', '2']).execute
    assert_includes @io.string, '• you had the last word'
    assert_includes @io.string, '(1 older messages omitted by --max)'
    refute_includes @io.string, 'earlier parent'
  end

  def test_invalid_context_options_fail_before_api
    assert_raises(Slk::UsageError) { command(['--max', '-1']) }
    assert_raises(Slk::UsageError) { command(['--before', 'abc']) }
    assert_raises(Slk::UsageError) { command(['--before', '201']) }
    assert_empty @client.calls
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

  def raw(timestamp, user, text, thread_ts: nil, reply_count: 0)
    { 'ts' => timestamp, 'user' => user, 'text' => text,
      'thread_ts' => thread_ts, 'reply_count' => reply_count }
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
                             cache_store: @cache_store, config: config, preset_store: presets)
    Slk::Commands::Sent.new(args, runner: runner)
  end
end
