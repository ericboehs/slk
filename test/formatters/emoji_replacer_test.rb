# frozen_string_literal: true

require 'test_helper'

class EmojiReplacerTest < Minitest::Test
  def setup
    @replacer = Slk::Formatters::EmojiReplacer.new
  end

  def test_replaces_common_emoji
    assert_equal "\u{1F44D}", @replacer.replace(':+1:')
    assert_equal "\u{1F525}", @replacer.replace(':fire:')
    assert_equal "\u{1F680}", @replacer.replace(':rocket:')
  end

  def test_leaves_unknown_emoji_unchanged
    assert_equal ':custom_emoji:', @replacer.replace(':custom_emoji:')
    assert_equal ':unknown_thing:', @replacer.replace(':unknown_thing:')
  end

  def test_replaces_multiple_emoji
    text = 'Hello :wave: how are you :smile:'
    result = @replacer.replace(text)
    assert_includes result, "\u{1F44B}"
    assert_includes result, "\u{1F604}"
    assert_includes result, 'Hello'
    assert_includes result, 'how are you'
  end

  def test_removes_skin_tone_modifiers
    assert_equal "\u{1F44D}", @replacer.replace(':+1::skin-tone-2:')
    assert_equal "\u{1F44B}", @replacer.replace(':wave::skin-tone-5:')
  end

  def test_preserves_text_around_emoji
    text = 'Start :fire: middle :star: end'
    result = @replacer.replace(text)
    assert_match(/^Start .+ middle .+ end$/, result)
  end

  def test_handles_text_without_emoji
    text = 'Hello world, no emoji here!'
    assert_equal text, @replacer.replace(text)
  end

  def test_handles_empty_text
    assert_equal '', @replacer.replace('')
  end

  def test_lookup_emoji_returns_unicode
    # These should return some unicode emoji (exact value may vary with gemoji cache)
    refute_nil @replacer.lookup_emoji('+1')
    refute_nil @replacer.lookup_emoji('fire')
    refute_nil @replacer.lookup_emoji('heart')

    # Verify they're actual unicode and not the :code: format
    refute_match(/^:.*:$/, @replacer.lookup_emoji('+1'))
  end

  def test_lookup_emoji_returns_nil_for_unknown
    assert_nil @replacer.lookup_emoji('definitely_not_an_emoji')
  end

  def test_common_emoji_coverage
    # Verify key emoji are in the map
    common = %w[smile thumbsup fire heart star rocket coffee pizza]
    common.each do |name|
      refute_nil @replacer.lookup_emoji(name), "Expected #{name} to be in emoji map"
    end
  end

  def test_emoji_regex_matches_valid_codes
    regex = Slk::Formatters::EmojiReplacer::EMOJI_REGEX
    assert_match regex, ':smile:'
    assert_match regex, ':+1:'
    assert_match regex, ':raised_hands:'
    assert_match regex, ':skin-tone-2:'
  end

  def test_emoji_regex_does_not_match_invalid
    regex = Slk::Formatters::EmojiReplacer::EMOJI_REGEX
    refute_match regex, 'smile'
    refute_match regex, ':'
    refute_match regex, '::'
  end

  def test_custom_emoji_returns_nil_skip
    replacer = Slk::Formatters::EmojiReplacer.new(custom_emoji: { 'foo' => 'https://...' })
    assert_nil replacer.lookup_emoji('foo')
  end

  def test_with_custom_emoji_creates_new_replacer
    replacer = Slk::Formatters::EmojiReplacer.new
    new_replacer = replacer.with_custom_emoji({ 'foo' => 'url' })
    refute_same replacer, new_replacer
    assert_nil new_replacer.lookup_emoji('foo')
  end

  def test_loads_gemoji_cache_when_present
    Dir.mktmpdir do |dir|
      old_xdg = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = dir
      cache_path = File.join(dir, 'slk', 'gemoji.json')
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, JSON.dump({ 'custom_thing' => "\u{1F389}" }))
      replacer = Slk::Formatters::EmojiReplacer.new
      assert_equal "\u{1F389}", replacer.lookup_emoji('custom_thing')
    ensure
      ENV['XDG_CACHE_HOME'] = old_xdg
    end
  end

  def test_loads_gemoji_cache_handles_corrupted_json
    Dir.mktmpdir do |dir|
      old_xdg = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = dir
      cache_path = File.join(dir, 'slk', 'gemoji.json')
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, '{not json')
      debug_msgs = []
      replacer = Slk::Formatters::EmojiReplacer.new(on_debug: ->(m) { debug_msgs << m })
      # Falls back to built-in map
      refute_nil replacer.lookup_emoji('fire')
      assert(debug_msgs.any? { |m| m.include?('Failed to load gemoji') })
    ensure
      ENV['XDG_CACHE_HOME'] = old_xdg
    end
  end

  def test_replace_with_workspace_arg_ignored
    # Second arg is reserved for future use
    assert_equal "\u{1F525}", @replacer.replace(':fire:', mock_workspace('test'))
  end

  def test_loads_gemoji_corrupted_json_without_on_debug
    Dir.mktmpdir do |dir|
      old_xdg = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = dir
      cache_path = File.join(dir, 'slk', 'gemoji.json')
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, '{not json')
      replacer = Slk::Formatters::EmojiReplacer.new # no on_debug
      refute_nil replacer.lookup_emoji('fire')
    ensure
      ENV['XDG_CACHE_HOME'] = old_xdg
    end
  end
end
