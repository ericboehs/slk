# frozen_string_literal: true

require 'test_helper'

class SlackUrlParserTest < Minitest::Test
  def setup
    @parser = SlackCli::Support::SlackUrlParser.new
  end

  def test_parses_channel_only_url
    result = @parser.parse('https://boehs.slack.com/archives/C0123ABC')

    assert_equal 'boehs', result.workspace
    assert_equal 'C0123ABC', result.channel_id
    assert_nil result.msg_ts
    assert_nil result.thread_ts
    refute result.message?
    refute result.thread?
  end

  def test_parses_message_url
    result = @parser.parse('https://boehs.slack.com/archives/C0123ABC/p1234567890123456')

    assert_equal 'boehs', result.workspace
    assert_equal 'C0123ABC', result.channel_id
    assert_equal '1234567890.123456', result.msg_ts
    assert_nil result.thread_ts
    assert result.message?
    refute result.thread?
  end

  def test_parses_thread_url
    result = @parser.parse('https://boehs.slack.com/archives/C0123ABC/p1234567890123456?thread_ts=1234567890.111111')

    assert_equal 'boehs', result.workspace
    assert_equal 'C0123ABC', result.channel_id
    assert_equal '1234567890.123456', result.msg_ts
    assert_equal '1234567890.111111', result.thread_ts
    assert result.message?
    assert result.thread?
  end

  def test_ts_returns_thread_ts_when_present
    result = @parser.parse('https://boehs.slack.com/archives/C0123ABC/p1234567890123456?thread_ts=1234567890.111111')

    # ts should return thread_ts for backward compatibility with thread fetching
    assert_equal '1234567890.111111', result.ts
  end

  def test_ts_returns_nil_when_no_thread
    result = @parser.parse('https://boehs.slack.com/archives/C0123ABC/p1234567890123456')

    # ts should be nil when it's not a thread (msg_ts should be used for oldest param)
    assert_nil result.ts
  end

  def test_slack_url_returns_true_for_valid_urls
    assert @parser.slack_url?('https://boehs.slack.com/archives/C0123ABC')
    assert @parser.slack_url?('https://test.slack.com/archives/C0123ABC/p123')
  end

  def test_slack_url_returns_false_for_invalid_urls
    refute @parser.slack_url?('https://google.com')
    refute @parser.slack_url?('boehs.slack.com')
    refute @parser.slack_url?('#general')
  end

  def test_parse_returns_nil_for_non_slack_url
    assert_nil @parser.parse('https://google.com')
    assert_nil @parser.parse('not-a-url')
  end

  def test_parses_group_dm_channel_id
    result = @parser.parse('https://boehs.slack.com/archives/G0123ABC/p1234567890123456')

    assert_equal 'G0123ABC', result.channel_id
  end
end
