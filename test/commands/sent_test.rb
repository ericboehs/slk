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
    dm = data['counts'].find { |row| row['channel_id'] == 'D2' }
    assert_equal 'U2', dm['channel_name']
    assert_equal '@U2', dm['channel_label']
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

  def test_dm_thread_uses_resolved_dm_label_and_thread_id
    sent = match('2.0', 'mine in thread', 'D2', 'U2', is_im: true).merge(
      'permalink' => 'https://slack.test/archives/D2/p2?thread_ts=1.0'
    )
    stub_matches('acme' => [sent])
    @cache_store.set_user('acme', 'U2', 'Katherine Johnson')
    @client.stub('conversations.replies', {
                   'messages' => [raw('1.0', 'U2', '').merge('files' => [{ 'name' => 'photo.png' }]),
                                  raw('2.0', 'U1', 'mine in thread', thread_ts: '1.0')]
                 })
    assert_equal 0, command(['-w', 'acme']).execute
    assert_includes @io.string, '[acme] @Katherine Johnson (thread: 1.0)'
    assert_includes @io.string, '[File: photo.png]'
    refute_includes @io.string, '(thread: "[file]")'
    refute_includes @io.string, '#U2'

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    thread = JSON.parse(@io.string)['conversations'].first
    assert_equal 'thread', thread['type']
    assert_equal 'U2', thread['channel_name']
    assert_equal '@Katherine Johnson', thread['channel_label']
  end

  def test_group_dm_header_and_json_count_show_participants_not_slug
    name = 'mpdm-ada.lovelace--eric.boehs--grace.hopper-1'
    sent = match('2.0', 'hello', 'G2', name).merge(
      'username' => 'eric.boehs', 'channel' => { 'id' => 'G2', 'name' => name, 'is_mpim' => true }
    )
    stub_matches('acme' => [sent])
    @cache_store.set_user('acme', 'U2', 'Ada Lovelace')
    @cache_store.set_user('acme', 'U3', 'Grace Hopper')
    @client.stub('conversations.info', { 'channel' => { 'members' => %w[U2 U1 U3] } })
    @client.stub('conversations.history', { 'messages' => [raw('2.0', 'U1', 'hello')] })
    assert_equal 0, command(['-w', 'acme']).execute
    assert_match(/^\[acme\] @Ada Lovelace, Grace Hopper$/, @io.string)
    refute_includes @io.string, 'mpdm-'

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    conversation = JSON.parse(@io.string)['conversations'].first
    assert_equal name, conversation['channel_name']
    assert_equal '@Ada Lovelace, Grace Hopper', conversation['channel_label']

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['-w', 'acme', '--mine', '--json']).execute
    count = JSON.parse(@io.string)['counts'].first
    assert_equal name, count['channel_name']
    assert_equal '@Ada Lovelace, Grace Hopper', count['channel_label']
  end

  def test_group_dm_falls_back_to_readable_handles_without_members_scope
    name = 'mpdm-ada.lovelace--eric.boehs--grace.hopper-1'
    sent = match('2.0', 'hello', 'G2', name).merge(
      'username' => 'eric.boehs', 'channel' => { 'id' => 'G2', 'name' => name, 'is_mpim' => true }
    )
    stub_matches('acme' => [sent])
    @client.stub('conversations.info', ->(_params) { raise Slk::ApiError, 'missing_scope' })
    assert_equal 0, command(['-w', 'acme', '--mine']).execute
    assert_includes @io.string, '[acme] @Ada Lovelace, Grace Hopper: 1'
    refute_includes @io.string, 'eric.boehs--'
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

  def test_following_history_includes_first_post_and_expands_its_thread
    sent = match('100.0', 'own post', 'C1', 'project').merge('username' => 'eric.boehs')
    stub_matches('acme' => [sent])
    @client.stub('conversations.history', lambda { |params|
      next { 'messages' => [] } unless params[:oldest] && params[:inclusive]

      { 'messages' => [raw('100.0', 'U1', 'own post', reply_count: 1).merge(
        'user_profile' => { 'display_name' => 'Eric Boehs' },
        'reactions' => [{ 'name' => 'tada', 'count' => 1, 'users' => ['U2'] }]
      )] }
    })
    @client.stub('conversations.replies', {
                   'messages' => [raw('100.0', 'U1', 'own post'),
                                  raw('101.0', 'U2', 'answer', thread_ts: '100.0')]
                 })
    assert_equal 0, command(['-w', 'acme']).execute
    assert_includes @io.string, 'Eric Boehs:'
    assert_includes @io.string, 'answer'
    assert_includes @io.string, '🎉'
    refute_includes @io.string, 'eric.boehs:'
    assert_equal true, @client.calls.find { |call| call[:params][:oldest] }[:params][:inclusive]
    reply_calls = @client.calls.count { |call| call[:method] == 'conversations.replies' }
    assert_equal 1, reply_calls
  end

  def test_expanded_replies_render_under_root_without_changing_flat_json_or_last_word
    stub_matches('acme' => [match('100.0', 'my root', 'C1', 'project')])
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => if params[:oldest]
                        [raw('110.0', 'U2', 'unrelated post'), raw('100.0', 'U1', 'my root', reply_count: 2)]
                      else
                        []
                      end }
    })
    @client.stub('conversations.replies', {
                   'messages' => [raw('100.0', 'U1', 'my root'), raw('120.0', 'U2', 'first reply', thread_ts: '100.0'),
                                  raw('121.0', 'U1', 'last reply', thread_ts: '100.0')]
                 })
    assert_equal 0, command(['-w', 'acme']).execute
    text = @io.string
    assert_operator text.index('my root'), :<, text.index('first reply')
    assert_operator text.index('first reply'), :<, text.index('last reply')
    assert_operator text.index('last reply'), :<, text.index('unrelated post')
    assert_match(/^    ↳ \[.*\] .*: first reply$/, text)
    assert_match(/^    ↳ \[.*\] .*: last reply$/, text)
    refute_includes text, '▶'
    refute_includes text, '• you had the last word'

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['-w', 'acme', '--json']).execute
    conversation = JSON.parse(@io.string)['conversations'].first
    assert_equal(%w[100.0 110.0 120.0 121.0], conversation['messages'].map { |row| row['ts'] })
    assert_equal(%w[100.0 100.0], conversation['messages'].last(2).map { |row| row['thread_ts'] })
    assert_equal true, conversation['last_speaker_is_me']
  end

  def test_dm_expanded_replies_also_render_under_root
    today = Date.today.to_time.to_i
    root = "#{today + 60}.0"
    stub_matches('acme' => [match(root, 'my DM root', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', {
                   'messages' => [raw(root, 'U1', 'my DM root', reply_count: 1),
                                  raw("#{today + 61}.0", 'U2', 'unrelated DM')]
                 })
    @client.stub('conversations.replies', {
                   'messages' => [raw(root, 'U1', 'my DM root'),
                                  raw("#{today + 62}.0", 'U2', 'DM thread reply', thread_ts: root)]
                 })
    assert_equal 0, command(['-w', 'acme']).execute
    assert_operator @io.string.index('DM thread reply'), :<, @io.string.index('unrelated DM')
    assert_match(/^    ↳ \[.*\] .*: DM thread reply$/, @io.string)
  end

  def test_orphaned_reply_from_max_keeps_parent_reference
    stub_matches('acme' => [match('100.0', 'my root', 'C1', 'project')])
    @client.stub('conversations.history', {
                   'messages' => [raw('100.0', 'U1', 'my root', reply_count: 1),
                                  raw('110.0', 'U2', 'unrelated post')]
                 })
    @client.stub('conversations.replies', {
                   'messages' => [raw('100.0', 'U1', 'my root'),
                                  raw('120.0', 'U2', 'late reply', thread_ts: '100.0')]
                 })
    assert_equal 0, command(['-w', 'acme', '--max', '2']).execute
    assert_match(/^    \(thread 100\.0\)$/, @io.string)
    assert_match(/^    ↳ \[.*\] .*: late reply$/, @io.string)
    assert_operator @io.string.index('unrelated post'), :<, @io.string.index('late reply')
  end

  def test_orphaned_reply_reference_does_not_consume_the_wrap_width
    root = '1790000000.123456'
    reply = '1790000001.123456'
    words = 'amber cobalt dolphin ember forest garden harbor island jungle lantern meadow'
    stub_matches('acme' => [match(root, 'my root', 'C1', 'project')])
    @client.stub('conversations.history', {
                   'messages' => [raw(root, 'U1', 'my root', reply_count: 1),
                                  raw('1790000000.999999', 'U2', 'other post')]
                 })
    @client.stub('conversations.replies', {
                   'messages' => [raw(root, 'U1', 'my root'), raw(reply, 'U2', words, thread_ts: root)]
                 })
    assert_equal 0, command(['-w', 'acme', '--max', '2', '--width', '52']).execute
    assert_match(/^    \(thread #{root}\)$/, @io.string)
    assert_match(/^    ↳ \[.*\] U2: amber/, @io.string)
    lines = @io.string.lines.map(&:chomp)
    assert(lines.all? { |line| Slk::Support::TextWrapper.visible_length(line) <= 52 }, lines.inspect)
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

  def test_context_decodes_unfurl_image_title_and_text
    stub_matches('acme' => [match('100.0', 'my post', 'C1', 'project')])
    attachment = { 'text' => 'Preview &amp; details &lt;here&gt;',
                   'title' => 'Introducing System One Models &amp; Jev - TypeSafe AI Blog',
                   'image_url' => 'https://example.com/image.png' }
    @client.stub('conversations.history', {
                   'messages' => [raw('100.0', 'U1', 'my post').merge('attachments' => [attachment])]
                 })
    assert_equal 0, command(['-w', 'acme']).execute
    assert_includes @io.string, 'Preview & details <here>'
    assert_includes @io.string, '[Image: Introducing System One Models & Jev - TypeSafe AI Blog]'
    refute_includes @io.string, '&amp;'
  end

  def test_mine_decodes_unfurl_image_title
    block = { 'type' => 'image', 'title' => { 'text' => 'One &amp; Two &lt;Three&gt;' } }
    match_with_unfurl = match('100.0', 'my post', 'C1', 'project').merge(
      'attachments' => [{ 'blocks' => [block] }]
    )
    stub_matches('acme' => [match_with_unfurl])
    assert_equal 0, command(['-w', 'acme', '--mine']).execute
    assert_includes @io.string, '[Image: One & Two <Three>]'
    refute_includes @io.string, '&amp;'
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

  def test_context_text_separates_conversations_with_width_aware_divider
    stub_matches('acme' => [match('100.0', 'first note', 'C1', 'orchard'),
                            match('200.0', 'second note', 'C2', 'harbor')])
    assert_equal 0, command(['-w', 'acme', '--before', '0', '--after-minutes', '0', '--width', '20']).execute
    text = @io.string
    assert_equal(1, text.lines.count { |line| line.chomp == '─' * 20 })
    assert_match(/first note\n\n─{20}\n\n\[acme\] #harbor/, text)
  end

  def test_context_text_shows_senders_without_status_markers
    stub_matches('acme' => [match('2.0', 'mine', 'C1', 'project')])
    @client.stub('conversations.history', { 'messages' => [raw('3.0', 'U2', 'their reply')] })
    assert_equal 0, command(['-w', 'acme', '--before', '0']).execute
    assert_match(/^\[acme\] #project$/, @io.string)
    refute_includes @io.string, '▶'
    assert_includes @io.string, 'mine'
    refute_includes @io.string, '↩ replied after you'
    refute_match(/^─+$/, @io.string)
  end

  def test_context_text_wraps_messages_with_indented_reply_continuations
    words = 'amber cobalt dolphin ember forest garden harbor island jungle lantern meadow'
    stub_matches('acme' => [match('100.0', words, 'C1', 'project')])
    @client.stub('conversations.history', {
                   'messages' => [raw('100.0', 'U1', words, reply_count: 1)]
                 })
    @client.stub('conversations.replies', {
                   'messages' => [raw('100.0', 'U1', words), raw('101.0', 'U2', words, thread_ts: '100.0')]
                 })
    assert_equal 0, command(['-w', 'acme', '--width', '48']).execute
    lines = @io.string.lines.map(&:chomp)
    assert(lines.all? { |line| Slk::Support::TextWrapper.visible_length(line) <= 48 })
    reply_index = lines.index { |line| line.start_with?('    ↳ ') }
    assert reply_index
    assert_match(/^ {6}\w/, lines.fetch(reply_index + 1))
    refute_includes @io.string, '▶'
  end

  def test_context_text_no_wrap_preserves_unbroken_message
    words = 'amber cobalt dolphin ember forest garden harbor island jungle lantern meadow'
    stub_matches('acme' => [match('100.0', words, 'C1', 'project')])
    assert_equal 0, command(['-w', 'acme', '--width', '48', '--no-wrap', '--before', '0',
                             '--after-minutes', '0']).execute
    assert(@io.string.lines.any? { |line| line.include?(words) })
  end

  def test_sent_uses_terminal_columns_as_default_wrap_width
    console = Struct.new(:winsize).new([24, 48])
    $stdout.stub(:tty?, true) do
      IO.stub(:console, console) { assert_equal 48, command([]).options[:width] }
    end
    $stdout.stub(:tty?, false) { assert_nil command([]).options[:width] }
  end

  def test_changed_text_wraps_heading_context_and_reply_without_repeating_parent_reference
    root = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    reply = "#{Time.local(2026, 9, 22, 15, 1).to_i}.0"
    old_text = 'old parent has enough words to wrap the heading and context'
    new_text = 'amber cobalt dolphin ember forest garden harbor island jungle lantern meadow'
    stub_matches('acme' => [match(root, old_text, 'C1', 'project')])
    @client.stub('conversations.replies', lambda { |params|
      messages = if params[:oldest]
                   [raw(reply, 'U2', new_text, thread_ts: root)]
                 else
                   [raw(root, 'U1', old_text), raw(reply, 'U2', new_text, thread_ts: root)]
                 end
      { 'messages' => messages }
    })
    assert_equal 0, command(changed_args('--width', '52')).execute
    lines = @io.string.lines.map(&:chomp)
    assert(lines.all? { |line| Slk::Support::TextWrapper.visible_length(line) <= 52 }, lines.inspect)
    assert_match(/^· \[/, @io.string)
    assert_match(/^  .*heading and context$/, @io.string)
    assert_match(/^    ↳ \[.*\] U2: amber/, @io.string)
    refute_includes @io.string, "(thread #{root})"
    refute_includes @io.string, '▶'
    refute_includes @io.string, '↩ replied after you'
    refute_includes @io.string, '• you had the last word'
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

  def test_max_text_notes_dropped_messages
    stub_matches('dsva' => [match('12.0', 'my DM', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', {
                   'messages' => [raw('12.0', 'U1', 'my DM'), raw('11.0', 'U2', 'earlier reply'),
                                  raw('10.0', 'U2', 'earlier parent')]
                 })
    assert_equal 0, command(['-w', 'dsva', '--max', '2']).execute
    refute_includes @io.string, '• you had the last word'
    assert_includes @io.string, '(1 older messages omitted by --max)'
    refute_includes @io.string, 'earlier parent'
  end

  def test_changed_since_early_morning_clock_uses_yesterday_in_json
    @client.stub('auth.test', { 'user_id' => 'U1' })
    now = Time.local(2026, 9, 22, 2, 0)
    Time.stub(:now, now) do
      Date.stub(:today, Date.new(2026, 9, 22)) do
        assert_equal 0, command(['-w', 'acme', '--changed-since', '16:00', '--json']).execute
      end
    end
    data = JSON.parse(@io.string)
    assert_equal Time.local(2026, 9, 21, 16, 0).iso8601, data['changed_since']['iso']
    assert_equal Slk::Support::CheckInTime.timestamp(Time.local(2026, 9, 21, 16, 0)),
                 data['changed_since']['ts']
    assert_equal 'from:me after:2026-09-15 before:2026-09-23', @client.calls.first[:params][:query]
  end

  def test_changed_since_accepts_single_digit_hour_in_cli
    @client.stub('auth.test', { 'user_id' => 'U1' })
    Time.stub(:now, Time.local(2026, 9, 22, 9, 0)) do
      Date.stub(:today, Date.new(2026, 9, 22)) do
        assert_equal 0, command(['-w', 'acme', '--changed-since', '8:00', '--json']).execute
      end
    end
    assert_equal Time.local(2026, 9, 22, 8, 0).iso8601, JSON.parse(@io.string)['changed_since']['iso']
  end

  def test_changed_since_finds_prior_day_thread_reply_and_marks_only_new_messages
    root = '1790000000.123456'
    reply = "#{Time.local(2026, 9, 22, 7, 13).to_i}.000001"
    stub_matches('acme' => [match(root, 'prior day post', 'C1', 'research')])
    @client.stub('conversations.replies', lambda { |params|
      { 'messages' => if params[:oldest]
                        [raw(reply, 'U2', 'new answer', thread_ts: root)]
                      else
                        [raw(root, 'U1', 'prior day post'), raw(reply, 'U2', 'new answer', thread_ts: root)]
                      end }
    })
    Date.stub(:today, Date.new(2026, 9, 22)) do
      assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T07:00',
                               '--lookback', '3', '--json']).execute
    end
    data = JSON.parse(@io.string)
    assert_equal Time.local(2026, 9, 22, 7, 0).iso8601, data['changed_since']['iso']
    assert_equal 3, data['lookback_days']
    assert_equal 1, data['conversations'].size
    conversation = data['conversations'].first
    assert_equal 1, conversation['new_count']
    assert_equal 1, conversation['new_from_others']
    assert_equal([false, true], conversation['messages'].map { |message| message['new'] })
    assert_equal root, conversation['thread_ts']
    assert_equal false, conversation['last_speaker_is_me']
    assert_equal 'from:me after:2026-09-19 before:2026-09-23', @client.calls.first[:params][:query]
    assert(@client.calls.any? { |call| call[:method] == 'conversations.replies' && call[:params][:oldest] })

    @io.truncate(0)
    @io.rewind
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T07:00']).execute
    assert_includes @io.string, '1 new (1 from others)'
    assert_match(/· .*prior day post/, @io.string)
    refute_includes @io.string, '── new since'
    assert_operator @io.string.index('prior day post'), :<, @io.string.index('new answer')
    assert_match(/^    ↳ \[.*\] .*: new answer$/, @io.string)
    refute_includes @io.string, "(thread #{root})"
  end

  def test_changed_since_pages_new_thread_replies_before_counting
    root = '1790000000.123456'
    reply1 = "#{Time.local(2026, 9, 22, 15, 1).to_i}.0"
    reply2 = "#{Time.local(2026, 9, 22, 15, 2).to_i}.0"
    stub_matches('acme' => [match(root, 'old root', 'C1', 'project')])
    @client.stub('conversations.replies', lambda { |params|
      if params[:cursor]
        { 'messages' => [raw(reply2, 'U2', 'second', thread_ts: root)] }
      elsif params[:oldest]
        { 'messages' => [raw(reply1, 'U1', 'first', thread_ts: root)], 'has_more' => true,
          'response_metadata' => { 'next_cursor' => 'p2' } }
      else
        { 'messages' => [raw(root, 'U1', 'old root'), raw(reply1, 'U1', 'first', thread_ts: root),
                         raw(reply2, 'U2', 'second', thread_ts: root)] }
      end
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    row = JSON.parse(@io.string)['conversations'].first
    assert_equal 2, row['new_count']
    assert_equal 1, row['new_from_others']
    cursor_calls = @client.calls.count { |call| call[:params][:cursor] == 'p2' }
    assert_equal 1, cursor_calls
  end

  def test_changed_since_does_not_include_busy_channel_without_my_new_post_or_thread_reply
    root = '1790000000.123456'
    stub_matches('acme' => [match(root, 'yesterday', 'C1', 'research')])
    @client.stub('conversations.history', { 'messages' => [raw(root, 'U1', 'yesterday')] })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    assert_equal [], JSON.parse(@io.string)['conversations']
    history_calls = @client.calls.count { |call| call[:method] == 'conversations.history' }
    assert_equal 1, history_calls
    refute(@client.calls.any? { |call| call[:method] == 'conversations.replies' })
  end

  def test_changed_since_batches_parent_metadata_and_fetches_only_active_thread
    since = Time.local(2026, 9, 22, 15, 0)
    root1 = "#{since.to_i - 86_400}.1"
    root2 = "#{since.to_i - 86_400}.2"
    reply = "#{since.to_i + 1}.0"
    stub_matches('acme' => [match(root1, 'idle', 'C1', 'project'), match(root2, 'active', 'C1', 'project')])
    @client.stub('conversations.history', {
                   'messages' => [raw(root1, 'U1', 'idle'),
                                  raw(root2, 'U1', 'active', reply_count: 1).merge('latest_reply' => reply)]
                 })
    @client.stub('conversations.replies', {
                   'messages' => [raw(root2, 'U1', 'active'), raw(reply, 'U2', 'answer', thread_ts: root2)]
                 })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    conversation = JSON.parse(@io.string)['conversations'].first
    assert_equal root2, conversation['thread_ts']
    history = @client.calls.select { |call| call[:method] == 'conversations.history' }
    replies = @client.calls.select { |call| call[:method] == 'conversations.replies' }
    assert_equal 1, history.size
    assert_equal true, history.first[:params][:inclusive]
    assert_equal 1, replies.size
    refute replies.first[:params].key?(:oldest)
  end

  def test_changed_since_channel_window_counts_only_my_new_post
    since = Time.local(2026, 9, 22, 15, 0)
    old = "#{since.to_i - 1}.0"
    mine = "#{since.to_i + 1}.0"
    other = "#{since.to_i + 2}.0"
    stub_matches('acme' => [match(mine, 'my post', 'C1', 'project')])
    @client.stub('conversations.replies', { 'messages' => [raw(mine, 'U1', 'my post')] })
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => if params[:oldest]
                        [raw(other, 'U2', 'busy channel'), raw(mine, 'U1', 'my post')]
                      else
                        [raw(old, 'U2', 'earlier context')]
                      end }
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    conversation = JSON.parse(@io.string)['conversations'].first
    assert_equal 'channel', conversation['type']
    assert_equal 1, conversation['new_count']
    assert_equal 0, conversation['new_from_others']
    assert_equal([false, true], conversation['messages'].map { |row| row['new'] })
    refute_includes conversation['messages'].map { |row| row['text'] }, 'busy channel'
  end

  def test_changed_since_dm_includes_new_message_from_other_even_when_my_post_was_yesterday
    since = Time.local(2026, 9, 22, 15, 0)
    prior = "#{since.to_i - 86_400}.0"
    latest = "#{since.to_i + 1}.0"
    stub_matches('acme' => [match(prior, 'old DM', 'D2', 'U2', is_im: true)])
    @client.stub('subscriptions.thread.getView', Slk::ApiError.new('missing_scope', code: :missing_scope))
    @client.stub('conversations.replies', { 'messages' => [] })
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => params[:oldest] ? [raw(latest, 'U2', 'new DM')] : [raw(prior, 'U1', 'old DM')] }
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00']).execute
    assert_includes @io.string, '1 new (1 from others)'
    assert_includes @io.string, '· '
    refute_includes @io.string, '── new since'
    assert_includes @io.string, 'new DM'
    assert_operator @io.string.index('old DM'), :<, @io.string.index('new DM')
  end

  def test_changed_since_dm_probe_avoids_full_history_when_quiet
    prior = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    stub_matches('acme' => [match(prior, 'old DM', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => params[:limit] == 1 ? [] : [raw(prior, 'U1', 'old DM')] }
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    assert_equal [], JSON.parse(@io.string)['conversations']
    history = @client.calls.select { |call| call[:method] == 'conversations.history' }
    assert_equal([200, 1], history.map { |call| call[:params][:limit] })
    refute(@client.calls.any? { |call| call[:method] == 'conversations.replies' })
  end

  def test_changed_since_unions_followed_thread_only_if_i_participated
    root = '1790000000.123456'
    reply = "#{Time.local(2026, 9, 22, 15, 13).to_i}.0"
    @client.stub('auth.test', { 'user_id' => 'U1' })
    @client.stub('subscriptions.thread.getView', {
                   'threads' => [{ 'root_msg' => { 'channel' => 'C1', 'thread_ts' => root, 'user' => 'U1' } }]
                 })
    @client.stub('conversations.info', { 'channel' => { 'name' => 'research' } })
    @client.stub('conversations.replies', lambda { |params|
      { 'messages' => if params[:oldest]
                        [raw(reply, 'U2', 'answer', thread_ts: root)]
                      else
                        [raw(root, 'U1', 'old root'), raw(reply, 'U2', 'answer', thread_ts: root)]
                      end }
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    conversation = JSON.parse(@io.string)['conversations'].first
    assert_equal 'thread', conversation['type']
    assert_equal 1, conversation['new_from_others']
  end

  def test_changed_since_ignores_followed_thread_i_never_joined
    root = '1790000000.123456'
    reply = "#{Time.local(2026, 9, 22, 15, 13).to_i}.0"
    @client.stub('auth.test', { 'user_id' => 'U1' })
    @client.stub('subscriptions.thread.getView', {
                   'threads' => [{ 'root_msg' => { 'channel' => 'C1', 'thread_ts' => root, 'user' => 'U3' } }]
                 })
    @client.stub('conversations.info', { 'channel' => { 'name' => 'project' } })
    @client.stub('conversations.replies', lambda { |params|
      messages = [raw(root, 'U3', 'old root'), raw(reply, 'U2', 'new answer', thread_ts: root)]
      { 'messages' => params[:oldest] ? messages.last(1) : messages }
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    assert_equal [], JSON.parse(@io.string)['conversations']
  end

  def test_changed_since_places_most_recent_conversation_last_across_midnight
    prior = "#{Time.local(2026, 9, 22, 16, 0).to_i}.0"
    yesterday = "#{Time.local(2026, 9, 22, 22, 1).to_i}.0"
    today = "#{Time.local(2026, 9, 23, 7, 45).to_i}.0"
    stub_matches('acme' => [match(prior, 'earlier note', 'D2', 'U2', is_im: true),
                            match(prior, 'earlier note', 'D3', 'U3', is_im: true)])
    @client.stub('conversations.history', lambda { |params|
      message = if params[:latest] || params[:oldest] == prior
                  raw(prior, 'U1', 'earlier note')
                elsif params[:channel] == 'D2'
                  raw(today, 'U2', 'today response')
                else
                  raw(yesterday, 'U3', 'yesterday response')
                end
      { 'messages' => [message] }
    })
    Time.stub(:now, Time.local(2026, 9, 23, 8, 0)) do
      Date.stub(:today, Date.new(2026, 9, 23)) do
        args = ['-w', 'acme', '--changed-since', '2026-09-22T18:00']
        assert_equal 0, command(args).execute
        text = @io.string
        assert_operator text.index('yesterday response'), :<, text.index('today response')
        assert_equal(1, text.lines.count { |line| line.chomp == '─' * 32 })
        assert_operator text.index('yesterday response'), :<, text.index('─' * 32)
        assert_operator text.index('─' * 32), :<, text.index('today response')
        refute_includes text, '── new since'
        @io.truncate(0)
        @io.rewind
        assert_equal 0, command(args + ['--json']).execute
      end
    end
    assert_equal(%w[D3 D2], JSON.parse(@io.string)['conversations'].map { |row| row['channel_id'] })
  end

  # rubocop:disable Metrics/PerceivedComplexity
  def test_changed_since_uses_strict_cutoff_and_sorts_by_latest_activity
    since = Time.local(2026, 9, 22, 15, 0)
    at_cutoff = "#{since.to_i}.000000"
    after = "#{since.to_i}.000001"
    later = "#{since.to_i + 1}.0"
    stub_matches('acme' => [match('1790000000.123456', 'older', 'D2', 'U2', is_im: true),
                            match('1790000000.123457', 'older', 'D3', 'U3', is_im: true)])
    @client.stub('conversations.replies', { 'messages' => [] })
    @client.stub('conversations.history', lambda { |params|
      if params[:latest]
        { 'messages' => [] }
      elsif params[:channel] == 'D2'
        { 'messages' => [raw(after, 'U1', 'own first'), raw(at_cutoff, 'U2', 'not new')] }
      else
        { 'messages' => [raw(later, 'U3', 'other last')] }
      end
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00', '--json']).execute
    rows = JSON.parse(@io.string)['conversations']
    assert_equal(%w[D2 D3], rows.map { |row| row['channel_id'] })
    assert_equal([1, 1], rows.map { |row| row['new_count'] })
    assert_equal([0, 1], rows.map { |row| row['new_from_others'] })
    assert(rows.flat_map { |row| row['messages'] }.all? { |message| message['new'] && message['ts'] != at_cutoff })
  end
  # rubocop:enable Metrics/PerceivedComplexity

  def test_changed_since_caps_output_without_changing_counts_or_last_speaker
    since = Time.local(2026, 9, 22, 15, 0)
    stamp = since.to_i
    stub_matches('acme' => [match('1790000000.123456', 'older', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.replies', { 'messages' => [] })
    @client.stub('conversations.history', lambda { |params|
      next { 'messages' => [] } if params[:latest]

      { 'messages' => [raw("#{stamp + 2}.0", 'U2', 'last'), raw("#{stamp + 1}.0", 'U1', 'first')] }
    })
    assert_equal 0, command(['-w', 'acme', '--changed-since', '2026-09-22T15:00',
                             '--context', '0', '--max', '1', '--json']).execute
    row = JSON.parse(@io.string)['conversations'].first
    assert_equal 2, row['new_count']
    assert_equal 1, row['new_from_others']
    assert_equal 1, row['dropped_messages']
    assert_equal false, row['last_speaker_is_me']
    assert_equal(["#{stamp + 2}.0"], row['messages'].map { |message| message['ts'] })
    refute(@client.calls.any? { |call| call[:method] == 'conversations.history' && call[:params][:latest] })
  end

  def test_changed_since_pages_parent_metadata_and_ignores_threads_last_active_before_cutoff
    since = Time.local(2026, 9, 22, 15, 0).to_i
    active = "#{since - 120}.1"
    quiet = "#{since - 60}.2"
    reply = "#{since + 1}.1"
    stub_matches('acme' => [match(active, 'active root', 'C1', 'project'),
                            match(quiet, 'quiet root', 'C1', 'project')])
    quiet_parent = raw(quiet, 'U1', 'quiet root', reply_count: 1).merge('latest_reply' => "#{since - 1}.0")
    @client.stub('conversations.history', lambda { |params|
      if params[:cursor]
        { 'messages' => [raw(active, 'U1', 'active root', reply_count: 1).merge('latest_reply' => reply)],
          'has_more' => true }
      else
        { 'messages' => [quiet_parent],
          'has_more' => true, 'response_metadata' => { 'next_cursor' => 'p2' } }
      end
    })
    @client.stub('conversations.replies', {
                   'messages' => [raw(active, 'U1', 'active root'), raw(reply, 'U2', 'answer', thread_ts: active)]
                 })
    assert_equal 0, command(changed_args('--json')).execute
    conversations = JSON.parse(@io.string)['conversations']
    assert_equal([active], conversations.map { |row| row['thread_ts'] })
    history = @client.calls.select { |call| call[:method] == 'conversations.history' }
    replies = @client.calls.select { |call| call[:method] == 'conversations.replies' }
    assert_equal([nil, 'p2'], history.map { |call| call[:params][:cursor] })
    assert_equal 1, replies.size
  end

  def test_changed_since_rejects_history_without_a_progressing_cursor
    root = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    stub_matches('acme' => [match(root, 'old root', 'C1', 'project')])
    @client.stub('conversations.history', { 'messages' => [], 'has_more' => true })
    assert_equal 1, command(changed_args('--json')).execute
    assert_empty @io.string
    assert_includes @err.string, 'has_more without a new cursor'
  end

  def test_changed_since_thread_only_search_hit_does_not_scan_channel_history
    root = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    own_reply = "#{Time.local(2026, 9, 21, 15, 1).to_i}.0"
    new_reply = "#{Time.local(2026, 9, 22, 15, 1).to_i}.0"
    hit = match(own_reply, 'mine', 'C1', 'project').merge(
      'permalink' => "https://slack.test/archives/C1/p2?thread_ts=#{root}"
    )
    stub_matches('acme' => [hit])
    @client.stub('conversations.replies', lambda { |params|
      messages = if params[:oldest]
                   [raw(new_reply, 'U2', 'new', thread_ts: root)]
                 else
                   [raw(root, 'U3', 'parent'), raw(own_reply, 'U1', 'mine', thread_ts: root),
                    raw(new_reply, 'U2', 'new', thread_ts: root)]
                 end
      { 'messages' => messages }
    })
    assert_equal 0, command(changed_args('--json')).execute
    row = JSON.parse(@io.string)['conversations'].first
    assert_equal 'thread', row['type']
    assert_equal 1, row['new_count']
    refute(@client.calls.any? { |call| call[:method] == 'conversations.history' })
  end

  def test_changed_since_treats_deleted_thread_as_unchanged_but_reports_other_api_errors
    root = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    stub_matches('acme' => [match(root, 'deleted root', 'C1', 'project')])
    @client.stub('conversations.history', { 'messages' => [] })
    @client.stub('conversations.replies', Slk::ApiError.new('thread_not_found'))
    assert_equal 0, command(changed_args('--json')).execute
    assert_equal [], JSON.parse(@io.string)['conversations']

    @io.truncate(0)
    @io.rewind
    @client.stub('conversations.replies', Slk::ApiError.new('not_in_channel'))
    assert_equal 1, command(changed_args('--json')).execute
    assert_empty @io.string
    assert_includes @err.string, 'not_in_channel'
  end

  def test_changed_since_subscriptions_skip_incomplete_roots_and_resolve_im_and_mpim
    root = '1790000000.123456'
    reply = "#{Time.local(2026, 9, 22, 15, 1).to_i}.1"
    @client.stub('auth.test', { 'user_id' => 'U1' })
    @client.stub('subscriptions.thread.getView', {
                   'threads' => [
                     { 'root_msg' => { 'channel' => 'C0' } },
                     { 'root_msg' => { 'channel' => 'C0', 'thread_ts' => root } },
                     { 'root_msg' => { 'channel' => 'D2', 'thread_ts' => root } },
                     { 'root_msg' => { 'channel' => 'G3', 'thread_ts' => root } }
                   ]
                 })
    @client.stub('conversations.info', lambda { |params|
      channel = case params[:channel]
                when 'D2' then { 'is_im' => true, 'user' => 'U2' }
                when 'G3' then { 'is_mpim' => true, 'name' => 'mpdm-ada.lovelace--eric.boehs--grace.hopper-1' }
                else {}
                end
      { 'channel' => channel }
    })
    @client.stub('conversations.replies', lambda { |params|
      messages = if params[:oldest]
                   [raw(reply, 'U2', 'answer', thread_ts: root)]
                 else
                   [raw(root, 'U1', 'old root'), raw(reply, 'U2', 'answer', thread_ts: root)]
                 end
      { 'messages' => messages }
    })
    assert_equal 0, command(changed_args('--json')).execute
    rows = JSON.parse(@io.string)['conversations']
    assert_equal(%w[D2 G3], rows.map { |row| row['channel_id'] })
    assert_equal 'U2', rows.first['channel_name']
    assert_equal 'mpdm-ada.lovelace--eric.boehs--grace.hopper-1', rows.last['channel_name']
    refute(@client.calls.any? { |call| call[:method] == 'conversations.replies' && call[:params][:channel] == 'C0' })
  end

  def test_changed_since_unavailable_subscriptions_are_optional_and_empty_text_is_clear
    @client.stub('auth.test', { 'user_id' => 'U1' })
    %i[missing_scope unknown_method not_allowed_token_type].each do |code|
      @client.stub('subscriptions.thread.getView', Slk::ApiError.new(code.to_s, code: code))
      assert_equal 0, command(changed_args).execute
      assert_includes @io.string, 'No changed sent conversations found.'
      refute_includes @err.string, code.to_s
      @io.truncate(0)
      @io.rewind
    end
  end

  def test_changed_since_subscription_failure_does_not_emit_partial_json
    @client.stub('auth.test', { 'user_id' => 'U1' })
    %i[network_error ratelimited unauthorized invalid_json].each do |code|
      @client.stub('subscriptions.thread.getView', Slk::ApiError.new(code.to_s, code: code))
      assert_equal 1, command(changed_args('--json')).execute
      assert_empty @io.string
      assert_includes @err.string, code.to_s
      @err.truncate(0)
      @err.rewind
    end
    @client.stub('subscriptions.thread.getView', Slk::ApiError.new('missing_scope'))
    assert_equal 1, command(changed_args('--json')).execute
    assert_empty @io.string
    assert_includes @err.string, 'missing_scope'
  end

  def test_changed_since_subscription_channel_lookup_failure_is_not_swallowed
    @client.stub('auth.test', { 'user_id' => 'U1' })
    @client.stub('subscriptions.thread.getView', {
                   'threads' => [{ 'root_msg' => { 'channel' => 'C1', 'thread_ts' => '1790000000.123456' } }]
                 })
    @client.stub('conversations.info', Slk::ApiError.new('missing_scope', code: :missing_scope))
    assert_equal 1, command(changed_args('--json')).execute
    assert_empty @io.string
    assert_includes @err.string, 'missing_scope'
  end

  def test_changed_since_sender_lookup_caches_authenticated_id
    @client.stub('auth.test', { 'user_id' => 'U1' })
    assert_equal 0, command(changed_args('--json')).execute
    assert_equal 'U1', @cache_store.get_meta('acme', 'self_user_id')
    @io.truncate(0)
    @io.rewind
    @client.stub('auth.test', Slk::ApiError.new('auth unavailable'))
    assert_equal 0, command(changed_args('--json')).execute
    assert_equal(1, @client.calls.count { |call| call[:method] == 'auth.test' })
  end

  def test_changed_since_missing_sender_id_reports_workspace_error
    @client.stub('auth.test', { 'ok' => true })
    assert_equal 1, command(changed_args('--json')).execute
    assert_empty @io.string
    assert_includes @err.string, 'Cannot identify sender in acme'
    refute_includes @err.string, 'KeyError'
    assert_nil @cache_store.get_meta('acme', 'self_user_id')
    refute(@client.calls.any? { |call| call[:method] == 'subscriptions.thread.getView' })
  end

  def test_changed_since_pages_busy_dm_after_probe_and_keeps_prior_context
    since = Time.local(2026, 9, 22, 15, 0).to_i
    root = "#{since - 86_400}.0"
    first = "#{since + 1}.0"
    second = "#{since + 2}.0"
    stub_matches('acme' => [match(root, 'old DM', 'D2', 'U2', is_im: true)])
    @client.stub('conversations.history', lambda { |params|
      if params[:latest] || params[:oldest] == root
        { 'messages' => [raw(root, 'U1', 'old DM')] }
      elsif params[:cursor]
        { 'messages' => [raw(second, 'U2', 'second')] }
      else
        { 'messages' => [raw(first, 'U2', 'first')], 'has_more' => true,
          'response_metadata' => { 'next_cursor' => 'p2' } }
      end
    })
    assert_equal 0, command(changed_args('--json')).execute
    row = JSON.parse(@io.string)['conversations'].first
    assert_equal 2, row['new_count']
    assert_equal 2, row['new_from_others']
    assert_equal([false, true, true], row['messages'].map { |message| message['new'] })
    history = @client.calls.select { |call| call[:method] == 'conversations.history' }
    assert_equal([200, 1, 200, 200, 2], history.map { |call| call[:params][:limit] })
  end

  def test_changed_since_own_new_dm_thread_is_not_repeated_in_dm_history
    since = Time.local(2026, 9, 22, 15, 0).to_i
    root = "#{since + 1}.0"
    reply = "#{since + 2}.0"
    stub_matches('acme' => [match(root, 'new DM root', 'D2', 'U2', is_im: true)])
    parent = raw(root, 'U1', 'new DM root', reply_count: 1).merge('latest_reply' => reply)
    @client.stub('conversations.history', { 'messages' => [parent] })
    @client.stub('conversations.replies', {
                   'messages' => [raw(root, 'U1', 'new DM root'), raw(reply, 'U2', 'answer', thread_ts: root)]
                 })
    assert_equal 0, command(changed_args('--json')).execute
    rows = JSON.parse(@io.string)['conversations']
    assert_equal 1, rows.size
    assert_equal 'thread', rows.first['type']
    assert_equal 2, rows.first['new_count']
    assert_equal([true, true], rows.first['messages'].map { |message| message['new'] })
  end

  def test_changed_since_own_channel_root_with_new_replies_is_not_duplicated_in_window
    since = Time.local(2026, 9, 22, 15, 0).to_i
    root = "#{since + 1}.0"
    reply = "#{since + 2}.0"
    parent = raw(root, 'U1', 'new post', reply_count: 1).merge('latest_reply' => reply)
    stub_matches('acme' => [match(root, 'new post', 'C1', 'project')])
    @client.stub('conversations.history', lambda { |params|
      { 'messages' => params[:latest] && !params[:oldest] ? [] : [parent] }
    })
    @client.stub('conversations.replies', {
                   'messages' => [parent, raw(reply, 'U2', 'answer', thread_ts: root)]
                 })
    assert_equal 0, command(changed_args('--json')).execute
    rows = JSON.parse(@io.string)['conversations']
    assert_equal 1, rows.size
    assert_equal 'thread', rows.first['type']
    assert_equal 2, rows.first['new_count']
    assert_equal([root, reply], rows.first['messages'].map { |message| message['ts'] })
  end

  def test_changed_since_missing_thread_parent_still_shows_reply_with_thread_id
    root = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    own_reply = "#{Time.local(2026, 9, 21, 15, 1).to_i}.0"
    new_reply = "#{Time.local(2026, 9, 22, 15, 1).to_i}.0"
    hit = match(own_reply, 'mine', 'C1', 'project').merge(
      'permalink' => "https://slack.test/archives/C1/p2?thread_ts=#{root}"
    )
    stub_matches('acme' => [hit])
    @client.stub('conversations.replies', {
                   'messages' => [raw(new_reply, 'U2', 'new answer', thread_ts: root)]
                 })
    assert_equal 0, command(changed_args('--max', '0')).execute
    assert_includes @io.string, "(thread: #{root})"
    refute_includes @io.string, '(thread: "[No text]")'
    assert_includes @io.string, '1 new (1 from others)'
    assert_includes @io.string, 'new answer'
    refute_includes @io.string, 'older messages omitted'
  end

  def test_changed_since_file_only_and_blank_thread_parents_show_same_thread_id
    root = "#{Time.local(2026, 9, 21, 15, 0).to_i}.0"
    own_reply = "#{Time.local(2026, 9, 21, 15, 1).to_i}.0"
    new_reply = "#{Time.local(2026, 9, 22, 15, 1).to_i}.0"
    hits = %w[C1 C2].map do |channel|
      match(own_reply, 'mine', channel, 'project').merge(
        'permalink' => "https://slack.test/archives/#{channel}/p2?thread_ts=#{root}"
      )
    end
    stub_matches('acme' => hits)
    @client.stub('conversations.replies', lambda { |params|
      parent = raw(root, 'U1', '')
      parent['files'] = [{ 'name' => 'plan.pdf' }] if params[:channel] == 'C1'
      messages = [parent, raw(new_reply, 'U2', 'answer', thread_ts: root)]
      { 'messages' => params[:oldest] ? messages.last(1) : messages }
    })
    assert_equal 0, command(changed_args).execute
    assert_equal 2, @io.string.scan("(thread: #{root})").size
    assert_includes @io.string, '[File: plan.pdf]'
    refute_includes @io.string, '(thread: "[No text]")'
    assert_equal 2, @io.string.scan('1 new (1 from others)').size
  end

  def test_sent_empty_mine_text_is_explicit
    assert_equal 0, command(['--mine', '-w', 'acme']).execute
    assert_includes @io.string, 'No sent messages found.'
  end

  def test_changed_since_epoch_json_preserves_microseconds
    time = Time.local(2026, 9, 22, 15, 0) + Rational(123_456, 1_000_000)
    timestamp = Slk::Support::CheckInTime.timestamp(time)
    @client.stub('auth.test', { 'user_id' => 'U1' })
    assert_equal 0, command(['-w', 'acme', '--changed-since', timestamp, '--json']).execute
    data = JSON.parse(@io.string)
    assert_equal timestamp, data['changed_since']['ts']
    assert_equal time.iso8601(6), data['changed_since']['iso']
  end

  def test_changed_since_rejects_conflicts_and_invalid_limits_before_search
    [%w[yesterday --changed-since 15:00], %w[--since 2026-09-21 --changed-since 15:00],
     %w[--changed-since 15:00 --mine], %w[--changed-since 15:00 --lookback 0],
     %w[--changed-since 15:00 --context -1]].each do |args|
      assert_raises(Slk::UsageError) { command(args).execute }
    end
    assert_empty @client.calls
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

  def changed_args(*options)
    ['-w', 'acme', '--changed-since', '2026-09-22T15:00', *options]
  end

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
