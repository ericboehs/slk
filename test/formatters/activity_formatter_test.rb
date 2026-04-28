# frozen_string_literal: true

require 'test_helper'

class ActivityFormatterTest < Minitest::Test
  def setup
    @output = test_output
    @workspace = mock_workspace('test')
    @debug = []
    @enricher = build_enricher
    @emoji = build_emoji
    @text_processor = build_text_processor
    @formatter = build_formatter
  end

  def test_display_all_with_no_items
    out = capture_stdout { @formatter.display_all([], @workspace, options: {}) }
    assert_match(/No activity found/, out)
  end

  def test_display_reaction
    item = reaction_item
    out = capture_stdout { @formatter.display_all([item], @workspace, options: {}) }
    assert_includes out, 'reacted'
    assert_includes out, 'in #general'
    assert_includes out, 'alice'
  end

  def test_display_reaction_with_message_preview
    item = reaction_item
    fetch = proc { |_w, _c, _ts| stub_message('Hello world from alice') }
    options = { show_messages: true, fetch_message: fetch }
    out = capture_stdout { @formatter.display_all([item], @workspace, options: options) }
    assert_includes out, '└─'
    assert_includes out, 'Hello world from alice'
  end

  def test_display_reaction_with_long_message_truncation_and_extra_lines
    long_text = "#{'A' * 150}\nsecond line\nthird line\nfourth line\nfifth line"
    fetch = proc { |_w, _c, _ts| stub_message(long_text) }
    options = { show_messages: true, fetch_message: fetch }
    out = capture_stdout { @formatter.display_all([reaction_item], @workspace, options: options) }
    assert_includes out, '...'
    assert_includes out, 'more lines'
  end

  def test_display_reaction_missing_data_calls_debug
    bad = { 'feed_ts' => '1', 'item' => { 'type' => 'message_reaction' } }
    capture_stdout { @formatter.display_all([bad], @workspace, options: {}) }
    assert_includes @debug.join, 'Could not display reaction'
  end

  def test_display_mention
    item = mention_item
    out = capture_stdout { @formatter.display_all([item], @workspace, options: {}) }
    assert_includes out, 'mentioned you'
    assert_includes out, '#general'
  end

  def test_display_mention_uses_author_user_id
    msg = { 'channel' => 'C1', 'author_user_id' => 'U2', 'text' => 'hi' }
    item = { 'feed_ts' => '1', 'item' => { 'type' => 'at_user', 'message' => msg } }
    out = capture_stdout { @formatter.display_all([item], @workspace, options: {}) }
    assert_includes out, 'mentioned you'
  end

  def test_display_mention_missing_message_calls_debug
    bad = { 'feed_ts' => '1', 'item' => { 'type' => 'at_user' } }
    capture_stdout { @formatter.display_all([bad], @workspace, options: {}) }
    assert_includes @debug.join, 'Could not display mention'
  end

  def test_display_thread
    item = thread_item
    out = capture_stdout { @formatter.display_all([item], @workspace, options: {}) }
    assert_includes out, 'Thread activity in #general'
  end

  def test_display_thread_with_show_messages
    fetch = proc { |_w, _c, _ts| stub_message('thread parent') }
    options = { show_messages: true, fetch_message: fetch }
    out = capture_stdout { @formatter.display_all([thread_item], @workspace, options: options) }
    assert_includes out, 'thread parent'
  end

  def test_display_thread_missing_data
    bad = { 'feed_ts' => '1', 'item' => { 'type' => 'thread_v2' } }
    capture_stdout { @formatter.display_all([bad], @workspace, options: {}) }
    assert_includes @debug.join, 'Could not display thread'
  end

  def test_display_bot_dm
    item = bot_dm_item
    out = capture_stdout { @formatter.display_all([item], @workspace, options: {}) }
    assert_includes out, 'Bot message'
  end

  def test_display_bot_dm_with_bot_id
    bot_msg = { 'channel' => 'C1', 'bot_id' => 'B1', 'text' => 'beep' }
    item = { 'feed_ts' => '1', 'item' => { 'type' => 'bot_dm_bundle',
                                           'bundle_info' => { 'payload' => { 'message' => bot_msg } } } }
    fetch = proc { |_w, _c, _ts| bot_msg.merge('text' => 'beep') }
    options = { show_messages: true, fetch_message: fetch }
    out = capture_stdout { @formatter.display_all([item], @workspace, options: options) }
    assert_includes out, 'Bot:'
  end

  def test_display_bot_dm_missing_payload
    bad = { 'feed_ts' => '1', 'item' => { 'type' => 'bot_dm_bundle' } }
    capture_stdout { @formatter.display_all([bad], @workspace, options: {}) }
    assert_includes @debug.join, 'Could not display bot DM'
  end

  def test_unknown_activity_type_logs_debug
    bad = { 'feed_ts' => '1', 'item' => { 'type' => 'mystery' } }
    capture_stdout { @formatter.display_all([bad], @workspace, options: {}) }
    assert_includes @debug.join, "Unknown activity type 'mystery'"
  end

  def test_message_with_unknown_user_when_no_user_or_bot
    fetch = proc { |_w, _c, _ts| { 'text' => 'no author' } }
    options = { show_messages: true, fetch_message: fetch }
    out = capture_stdout { @formatter.display_all([reaction_item], @workspace, options: options) }
    assert_includes out, 'Unknown:'
  end

  def test_show_message_preview_skipped_without_show_messages
    fetch_called = false
    fetch = proc { |_w, _c, _ts|
      fetch_called = true
      nil
    }
    options = { fetch_message: fetch } # no :show_messages
    capture_stdout { @formatter.display_all([reaction_item], @workspace, options: options) }
    refute fetch_called
  end

  def test_show_message_preview_skipped_without_fetcher
    options = { show_messages: true } # no :fetch_message
    out = capture_stdout { @formatter.display_all([reaction_item], @workspace, options: options) }
    refute_includes out, '└─'
  end

  def test_dispatch_unknown_type_with_nil_does_not_call_debug
    bad = { 'feed_ts' => '1', 'item' => { 'type' => nil } }
    capture_stdout { @formatter.display_all([bad], @workspace, options: {}) }
    refute(@debug.any? { |m| m.include?('Unknown') })
  end

  def test_show_message_preview_returns_when_message_nil
    fetch = proc { |_w, _c, _ts| }
    options = { show_messages: true, fetch_message: fetch }
    out = capture_stdout { @formatter.display_all([reaction_item], @workspace, options: options) }
    refute_includes out, '└─'
  end

  def test_thread_with_show_messages_no_thread_ts
    item = {
      'feed_ts' => '1', 'item' => {
        'type' => 'thread_v2',
        'bundle_info' => { 'payload' => { 'thread_entry' => { 'channel_id' => 'C1' } } }
      }
    }
    fetch_called = false
    fetch = proc { |_w, _c, _ts|
      fetch_called = true
      stub_message('hi')
    }
    options = { show_messages: true, fetch_message: fetch }
    capture_stdout { @formatter.display_all([item], @workspace, options: options) }
    refute fetch_called
  end

  private

  def stub_message(text, user: 'U1')
    { 'text' => text, 'user' => user }
  end

  def reaction_item
    {
      'feed_ts' => '1700000000.000000',
      'item' => {
        'type' => 'message_reaction',
        'reaction' => { 'user' => 'U1', 'name' => 'thumbsup' },
        'message' => { 'channel' => 'C1', 'ts' => '1700000000.0' }
      }
    }
  end

  def mention_item
    {
      'feed_ts' => '1700000000.000000',
      'item' => {
        'type' => 'at_user',
        'message' => { 'channel' => 'C1', 'user' => 'U1', 'text' => 'hey' }
      }
    }
  end

  def thread_item
    {
      'feed_ts' => '1700000000.000000',
      'item' => {
        'type' => 'thread_v2',
        'bundle_info' => { 'payload' => { 'thread_entry' => { 'channel_id' => 'C1', 'thread_ts' => '1.0' } } }
      }
    }
  end

  def bot_dm_item
    {
      'feed_ts' => '1700000000.000000',
      'item' => {
        'type' => 'bot_dm_bundle',
        'bundle_info' => { 'payload' => { 'message' => { 'channel' => 'C1', 'bot_id' => 'B1', 'text' => 'beep' } } }
      }
    }
  end

  def build_formatter
    Slk::Formatters::ActivityFormatter.new(
      output: @output,
      enricher: @enricher,
      emoji_replacer: @emoji,
      text_processor: @text_processor,
      on_debug: ->(m) { @debug << m }
    )
  end

  def build_enricher
    Object.new.tap do |e|
      e.define_singleton_method(:resolve_user) { |_w, uid| uid == 'U1' ? 'alice' : "user-#{uid}" }
      e.define_singleton_method(:resolve_channel) { |_w, _c| '#general' }
    end
  end

  def build_emoji
    Object.new.tap do |e|
      e.define_singleton_method(:lookup_emoji) { |name| name == 'thumbsup' ? "\u{1F44D}" : nil }
    end
  end

  def build_text_processor
    Object.new.tap do |t|
      t.define_singleton_method(:process) { |text, _w| text.to_s }
    end
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
