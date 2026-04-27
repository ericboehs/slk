# frozen_string_literal: true

require 'test_helper'

class UnreadMarkerTest < Minitest::Test
  def setup
    @conversations = FakeConversationsApi.new
    @threads = FakeThreadsApi.new
    @client = FakeClientApi.new
    @users = FakeUsersApi.new
  end

  def test_mark_all_returns_zero_counts_when_no_unreads
    @client.counts_response = { 'ims' => [], 'channels' => [] }
    @threads.view_response = { 'ok' => true, 'threads' => [] }

    result = build_marker.mark_all

    assert_equal({ dms: 0, channels: 0, threads: 0 }, result)
  end

  def test_mark_all_marks_dms_with_unreads
    @client.counts_response = build_counts(ims: [{ 'id' => 'D1', 'has_unreads' => true }])
    @conversations.history_response = { 'messages' => [{ 'ts' => '1.0' }] }

    result = build_marker.mark_all

    assert_equal 1, result[:dms]
    assert_equal 'D1', @conversations.last_mark[:channel]
  end

  def test_mark_all_skips_dms_without_unreads
    @client.counts_response = build_counts(ims: [{ 'id' => 'D1', 'has_unreads' => false }])
    assert_equal 0, build_marker.mark_all[:dms]
  end

  def test_mark_all_skips_muted_channels_by_default
    @users.muted_channels_list = %w[C1]
    @client.counts_response = build_counts(channels: [{ 'id' => 'C1', 'has_unreads' => true }])

    assert_equal 0, build_marker.mark_all[:channels]
  end

  def test_mark_all_includes_muted_when_option_true
    @users.muted_channels_list = %w[C1]
    @client.counts_response = build_counts(channels: [{ 'id' => 'C1', 'has_unreads' => true }])
    @conversations.history_response = { 'messages' => [{ 'ts' => '5.0' }] }

    assert_equal 1, build_marker.mark_all(options: { muted: true })[:channels]
  end

  def test_mark_conversation_returns_false_with_no_messages
    @client.counts_response = build_counts(ims: [{ 'id' => 'D1', 'has_unreads' => true }])
    @conversations.history_response = { 'messages' => [] }

    assert_equal 0, build_marker.mark_all[:dms]
  end

  def test_mark_conversation_handles_api_error_with_debug
    @client.counts_response = build_counts(ims: [{ 'id' => 'D1', 'has_unreads' => true }])
    @conversations.raise_on_history = Slk::ApiError.new('boom', code: :error)
    debug_msgs = []
    marker = build_marker(on_debug: ->(m) { debug_msgs << m })

    assert_equal 0, marker.mark_all[:dms]
    assert(debug_msgs.any? { |m| m.include?('Could not mark D1') })
  end

  def test_mark_threads_returns_zero_when_view_not_ok
    @client.counts_response = build_counts
    @threads.view_response = { 'ok' => false }
    assert_equal 0, build_marker.mark_all[:threads]
  end

  def test_mark_threads_marks_threads_with_unread_replies
    @client.counts_response = build_counts
    @threads.view_response = { 'ok' => true, 'threads' => [thread_with_unread] }

    assert_equal 1, build_marker.mark_all[:threads]
    assert_equal '5.0', @threads.last_mark[:timestamp]
  end

  def test_mark_threads_skips_threads_without_unread
    @client.counts_response = build_counts
    @threads.view_response = { 'ok' => true, 'threads' => [{ 'unread_replies' => [] }] }

    assert_equal 0, build_marker.mark_all[:threads]
  end

  def test_mark_thread_handles_api_error
    @client.counts_response = build_counts
    @threads.view_response = { 'ok' => true, 'threads' => [thread_with_unread] }
    @threads.raise_on_mark = Slk::ApiError.new('thread fail', code: :error)
    debug = []
    marker = build_marker(on_debug: ->(m) { debug << m })

    assert_equal 0, marker.mark_all[:threads]
    assert(debug.any? { |m| m.include?('Could not mark thread') })
  end

  def test_mark_conversation_without_on_debug_swallows_error
    @client.counts_response = build_counts(ims: [{ 'id' => 'D1', 'has_unreads' => true }])
    @conversations.raise_on_history = Slk::ApiError.new('boom', code: :error)

    # No on_debug callback - exercise the &.call nil branch
    assert_equal 0, build_marker.mark_all[:dms]
  end

  def test_mark_thread_without_on_debug_swallows_error
    @client.counts_response = build_counts
    @threads.view_response = { 'ok' => true, 'threads' => [thread_with_unread] }
    @threads.raise_on_mark = Slk::ApiError.new('thread fail', code: :error)

    # No on_debug callback
    assert_equal 0, build_marker.mark_all[:threads]
  end

  def test_mark_channels_with_mixed_unread_states
    @client.counts_response = build_counts(channels: [
                                             { 'id' => 'C1', 'has_unreads' => true },
                                             { 'id' => 'C2', 'has_unreads' => false }
                                           ])
    @conversations.history_response = { 'messages' => [{ 'ts' => '5.0' }] }

    assert_equal 1, build_marker.mark_all[:channels]
  end

  def test_mark_conversation_with_nil_messages
    @client.counts_response = build_counts(ims: [{ 'id' => 'D1', 'has_unreads' => true }])
    @conversations.history_response = { 'messages' => nil }

    assert_equal 0, build_marker.mark_all[:dms]
  end

  def test_mark_single_channel_delegates
    @conversations.history_response = { 'messages' => [{ 'ts' => '1.0' }] }
    assert build_marker.mark_single_channel('C99')
    assert_equal 'C99', @conversations.last_mark[:channel]
  end

  private

  def build_marker(on_debug: nil)
    Slk::Services::UnreadMarker.new(
      conversations_api: @conversations, threads_api: @threads,
      client_api: @client, users_api: @users, on_debug: on_debug
    )
  end

  def build_counts(ims: [], channels: [])
    { 'ims' => ims, 'channels' => channels }
  end

  def thread_with_unread
    { 'unread_replies' => [{ 'ts' => '4.0' }, { 'ts' => '5.0' }],
      'root_msg' => { 'channel' => 'C1', 'thread_ts' => '3.0' } }
  end

  class FakeConversationsApi
    attr_accessor :history_response, :raise_on_history
    attr_reader :last_mark

    def history(channel:, limit: 1) # rubocop:disable Lint/UnusedMethodArgument
      raise @raise_on_history if @raise_on_history

      @history_response || { 'messages' => [] }
    end

    def mark(channel:, timestamp:)
      @last_mark = { channel: channel, timestamp: timestamp }
    end
  end

  class FakeThreadsApi
    attr_accessor :view_response, :raise_on_mark
    attr_reader :last_mark

    def get_view(limit: 50) # rubocop:disable Lint/UnusedMethodArgument
      @view_response || { 'ok' => true, 'threads' => [] }
    end

    def mark(channel:, thread_ts:, timestamp:)
      raise @raise_on_mark if @raise_on_mark

      @last_mark = { channel: channel, thread_ts: thread_ts, timestamp: timestamp }
    end
  end

  class FakeClientApi
    attr_accessor :counts_response

    def counts
      @counts_response || { 'ims' => [], 'channels' => [] }
    end
  end

  class FakeUsersApi
    attr_accessor :muted_channels_list

    def muted_channels
      @muted_channels_list || []
    end
  end
end
