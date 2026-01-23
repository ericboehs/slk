# frozen_string_literal: true

require_relative '../test_helper'

class SearchResultTest < Minitest::Test
  def test_from_api_creates_search_result
    match = build_match_data

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal '1234567890.123456', result.ts
    assert_equal 'U12345', result.user_id
    assert_equal 'john.doe', result.username
    assert_equal 'Hello world', result.text
    assert_equal 'C12345', result.channel_id
    assert_equal 'general', result.channel_name
    assert_equal 'channel', result.channel_type
  end

  def test_from_api_with_im_channel
    match = build_match_data(channel: { 'id' => 'D12345', 'name' => 'john', 'is_im' => true })

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal 'im', result.channel_type
    assert result.dm?
  end

  def test_from_api_with_mpim_channel
    match = build_match_data(channel: { 'id' => 'G12345', 'name' => 'group', 'is_mpim' => true })

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal 'mpim', result.channel_type
    assert result.dm?
  end

  def test_timestamp_returns_time_object
    match = build_match_data(ts: '1704067200.000000')

    result = Slk::Models::SearchResult.from_api(match)

    assert_instance_of Time, result.timestamp
    assert_equal Time.at(1_704_067_200.0), result.timestamp
  end

  def test_display_channel_for_regular_channel
    match = build_match_data

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal '#general', result.display_channel
  end

  def test_display_channel_for_dm
    match = build_match_data(channel: { 'id' => 'D12345', 'name' => 'john', 'is_im' => true })

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal '@john', result.display_channel
  end

  def test_extracts_thread_ts_from_permalink
    match = build_match_data(
      permalink: 'https://workspace.slack.com/archives/C12345/p1234567890123456?thread_ts=1234500000.000000'
    )

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal '1234500000.000000', result.thread_ts
    assert result.thread?
  end

  def test_thread_false_without_thread_ts
    match = build_match_data(permalink: 'https://workspace.slack.com/archives/C12345/p1234567890123456')

    result = Slk::Models::SearchResult.from_api(match)

    assert_nil result.thread_ts
    refute result.thread?
  end

  def test_handles_missing_user
    match = build_match_data(user: nil, username: 'bot_user')

    result = Slk::Models::SearchResult.from_api(match)

    assert_equal 'bot_user', result.user_id
  end

  private

  def build_match_data(overrides = {})
    {
      'ts' => '1234567890.123456',
      'user' => 'U12345',
      'username' => 'john.doe',
      'text' => 'Hello world',
      'channel' => { 'id' => 'C12345', 'name' => 'general' },
      'permalink' => 'https://workspace.slack.com/archives/C12345/p1234567890123456'
    }.merge(overrides.transform_keys(&:to_s))
  end
end
