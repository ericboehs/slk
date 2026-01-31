# frozen_string_literal: true

require 'test_helper'

class TextProcessorTest < Minitest::Test
  # Mock mention replacer
  class MockMentionReplacer
    def replace(text, _workspace)
      text.gsub(/<@U[A-Z0-9]+>/, '@user')
    end
  end

  # Mock emoji replacer
  class MockEmojiReplacer
    def replace(text, _workspace = nil)
      text.gsub(':smile:', '😄')
    end
  end

  def setup
    @mention_replacer = MockMentionReplacer.new
    @emoji_replacer = MockEmojiReplacer.new
    @processor = Slk::Formatters::TextProcessor.new(
      mention_replacer: @mention_replacer,
      emoji_replacer: @emoji_replacer
    )
    @workspace = mock_workspace('test')
  end

  def test_process_returns_no_text_for_nil
    result = @processor.process(nil, @workspace)
    assert_equal '[No text]', result
  end

  def test_process_returns_no_text_for_empty_string
    result = @processor.process('', @workspace)
    assert_equal '[No text]', result
  end

  def test_process_decodes_html_entities
    result = @processor.process('Hello &amp; goodbye &lt;world&gt;', @workspace)
    assert_equal 'Hello & goodbye <world>', result
  end

  def test_process_replaces_mentions
    result = @processor.process('Hello <@U123ABC>', @workspace)
    assert_equal 'Hello @user', result
  end

  def test_process_replaces_emoji
    result = @processor.process('Hello :smile:', @workspace)
    assert_equal 'Hello 😄', result
  end

  def test_process_applies_all_transformations
    result = @processor.process('Hello &amp; <@U123ABC> :smile:', @workspace)
    assert_equal 'Hello & @user 😄', result
  end

  def test_process_skips_emoji_when_option_set
    result = @processor.process('Hello :smile:', @workspace, no_emoji: true)
    assert_equal 'Hello :smile:', result
  end

  def test_process_skips_mentions_when_option_set
    result = @processor.process('Hello <@U123ABC>', @workspace, no_mentions: true)
    assert_equal 'Hello <@U123ABC>', result
  end

  def test_process_skips_both_when_options_set
    result = @processor.process('Hello <@U123ABC> :smile:', @workspace, no_emoji: true, no_mentions: true)
    # HTML entities are still decoded
    assert_equal 'Hello <@U123ABC> :smile:', result
  end

  def test_process_decodes_html_even_when_replacements_skipped
    result = @processor.process('Hello &amp; world', @workspace, no_emoji: true, no_mentions: true)
    assert_equal 'Hello & world', result
  end

  def test_process_handles_text_with_only_whitespace
    result = @processor.process('   ', @workspace)
    assert_equal '   ', result
  end

  def test_process_preserves_newlines
    result = @processor.process("Hello\nWorld", @workspace)
    assert_equal "Hello\nWorld", result
  end
end
