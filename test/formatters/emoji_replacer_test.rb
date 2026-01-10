# frozen_string_literal: true

require "test_helper"

class EmojiReplacerTest < Minitest::Test
  def setup
    @replacer = SlackCli::Formatters::EmojiReplacer.new
  end

  def test_replaces_common_emoji
    assert_equal "\u{1F44D}", @replacer.replace(":+1:")
    assert_equal "\u{1F525}", @replacer.replace(":fire:")
    assert_equal "\u{1F680}", @replacer.replace(":rocket:")
  end

  def test_leaves_unknown_emoji_unchanged
    assert_equal ":custom_emoji:", @replacer.replace(":custom_emoji:")
    assert_equal ":unknown_thing:", @replacer.replace(":unknown_thing:")
  end

  def test_replaces_multiple_emoji
    text = "Hello :wave: how are you :smile:"
    result = @replacer.replace(text)
    assert_includes result, "\u{1F44B}"
    assert_includes result, "\u{1F604}"
    assert_includes result, "Hello"
    assert_includes result, "how are you"
  end

  def test_removes_skin_tone_modifiers
    assert_equal "\u{1F44D}", @replacer.replace(":+1::skin-tone-2:")
    assert_equal "\u{1F44B}", @replacer.replace(":wave::skin-tone-5:")
  end

  def test_preserves_text_around_emoji
    text = "Start :fire: middle :star: end"
    result = @replacer.replace(text)
    assert_match(/^Start .+ middle .+ end$/, result)
  end

  def test_handles_text_without_emoji
    text = "Hello world, no emoji here!"
    assert_equal text, @replacer.replace(text)
  end

  def test_handles_empty_text
    assert_equal "", @replacer.replace("")
  end

  def test_lookup_emoji_returns_unicode
    # These should return some unicode emoji (exact value may vary with gemoji cache)
    refute_nil @replacer.lookup_emoji("+1")
    refute_nil @replacer.lookup_emoji("fire")
    refute_nil @replacer.lookup_emoji("heart")

    # Verify they're actual unicode and not the :code: format
    refute_match(/^:.*:$/, @replacer.lookup_emoji("+1"))
  end

  def test_lookup_emoji_returns_nil_for_unknown
    assert_nil @replacer.lookup_emoji("definitely_not_an_emoji")
  end

  def test_common_emoji_coverage
    # Verify key emoji are in the map
    common = %w[smile thumbsup fire heart star rocket coffee pizza]
    common.each do |name|
      refute_nil @replacer.lookup_emoji(name), "Expected #{name} to be in emoji map"
    end
  end

  def test_emoji_regex_matches_valid_codes
    regex = SlackCli::Formatters::EmojiReplacer::EMOJI_REGEX
    assert_match regex, ":smile:"
    assert_match regex, ":+1:"
    assert_match regex, ":raised_hands:"
    assert_match regex, ":skin-tone-2:"
  end

  def test_emoji_regex_does_not_match_invalid
    regex = SlackCli::Formatters::EmojiReplacer::EMOJI_REGEX
    refute_match regex, "smile"
    refute_match regex, ":"
    refute_match regex, "::"
  end
end
