# frozen_string_literal: true

require_relative '../test_helper'

class SearchFormatterTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @mention_replacer = MockMentionReplacer.new
    @text_processor = MockTextProcessor.new
    @formatter = Slk::Formatters::SearchFormatter.new(
      output: @output,
      mention_replacer: @mention_replacer,
      text_processor: @text_processor
    )
    @workspace = mock_workspace('test')
  end

  def test_display_result_for_regular_channel
    result = build_search_result(channel_type: 'channel', channel_name: 'general')

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, '#general'
    assert_includes output, 'john.doe:'
    assert_includes output, 'Hello world'
  end

  def test_display_result_for_dm_channel
    result = build_search_result(channel_type: 'im', channel_name: 'U12345')

    @formatter.display_result(result, @workspace)

    output = @io.string
    # DM channels should resolve the user ID via mention replacer
    assert_includes output, '@resolved_U12345'
  end

  def test_display_result_with_files
    result = build_search_result(files: [{ name: 'screenshot.png', type: 'image' }])

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, '[Image: screenshot.png]'
  end

  def test_display_result_with_multiple_files
    result = build_search_result(files: [
                                   { name: 'file1.png', type: 'image' },
                                   { name: 'file2.jpg', type: 'image' }
                                 ])

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, '[Image: file1.png]'
    assert_includes output, '[Image: file2.jpg]'
  end

  def test_display_result_replaces_emoji
    result = build_search_result(text: 'Hello :wave: world')

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, 'Hello [emoji:wave] world'
  end

  def test_display_result_replaces_mentions
    result = build_search_result(text: 'Hey <@U999> check this')

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, '@resolved_U999'
  end

  def test_display_result_with_no_emoji_option
    result = build_search_result(text: 'Hello :wave: world')

    @formatter.display_result(result, @workspace, { no_emoji: true })

    output = @io.string
    # Emoji should NOT be replaced
    assert_includes output, ':wave:'
    refute_includes output, '[emoji:wave]'
  end

  def test_display_result_with_no_mentions_option
    result = build_search_result(text: 'Hey <@U999> check this')

    @formatter.display_result(result, @workspace, { no_mentions: true })

    output = @io.string
    # Mentions should NOT be replaced
    assert_includes output, '<@U999>'
  end

  def test_resolve_user_with_username
    result = build_search_result(username: 'john.doe', user_id: 'U12345')

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, 'john.doe:'
    refute_includes output, '@resolved_U12345:'
  end

  def test_resolve_user_with_empty_username_falls_back_to_user_id
    result = build_search_result(username: '', user_id: 'U12345')

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, '@resolved_U12345:'
  end

  def test_resolve_user_with_nil_username_falls_back_to_user_id
    result = build_search_result(username: nil, user_id: 'U12345')

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, '@resolved_U12345:'
  end

  def test_resolve_user_with_nil_user_id_shows_unknown
    result = build_search_result(username: nil, user_id: nil)

    @formatter.display_result(result, @workspace)

    output = @io.string
    assert_includes output, 'Unknown User:'
  end

  def test_display_all_with_empty_results
    @formatter.display_all([], @workspace)

    assert_includes @io.string, 'No results found.'
  end

  def test_display_all_with_multiple_results
    results = [
      build_search_result(text: 'First message'),
      build_search_result(text: 'Second message')
    ]

    @formatter.display_all(results, @workspace)

    output = @io.string
    assert_includes output, 'First message'
    assert_includes output, 'Second message'
  end

  def test_display_result_shows_timestamp
    # Create a result with a known timestamp
    result = build_search_result(ts: '1704067200.000000') # 2024-01-01 00:00:00 UTC

    @formatter.display_result(result, @workspace)

    output = @io.string
    # Timestamp should be formatted
    assert_match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]/, output)
  end

  private

  def build_search_result(overrides = {})
    defaults = {
      ts: '1234567890.123456',
      user_id: 'U12345',
      username: 'john.doe',
      text: 'Hello world',
      channel_id: 'C12345',
      channel_name: 'general',
      channel_type: 'channel',
      thread_ts: nil,
      permalink: 'https://workspace.slack.com/archives/C12345/p1234567890123456',
      files: []
    }

    Slk::Models::SearchResult.new(**defaults, **overrides)
  end

  # Mock text processor for testing
  class MockTextProcessor
    def process(text, _workspace, options = {})
      return '[No text]' if text.to_s.empty?

      result = text
      result = result.gsub(/<@(\w+)>/, '@resolved_\1') unless options[:no_mentions]
      result = result.gsub(/:(\w+):/, '[emoji:\1]') unless options[:no_emoji]
      result
    end
  end

  # Mock mention replacer for testing (used for resolve_channel/resolve_user)
  class MockMentionReplacer
    def replace(text, _workspace)
      text.gsub(/<@(\w+)>/, '@resolved_\1')
    end
  end
end
