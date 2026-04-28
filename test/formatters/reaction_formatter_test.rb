# frozen_string_literal: true

require 'test_helper'

class ReactionFormatterTest < Minitest::Test
  # Minimal cache stub
  class FakeCache
    def initialize
      @users = {}
    end

    def get_user(workspace, user_id)
      @users["#{workspace}:#{user_id}"]
    end

    def set_user(workspace, user_id, name)
      @users["#{workspace}:#{user_id}"] = name
    end
  end

  # Stand-in EmojiReplacer that maps known names to glyphs
  class FakeEmojiReplacer
    def initialize(map = {})
      @map = map
    end

    def lookup_emoji(name)
      @map[name]
    end
  end

  def setup
    @output = test_output(color: false)
    @cache = FakeCache.new
    @emoji = FakeEmojiReplacer.new('thumbsup' => "\u{1F44D}", 'heart' => "\u{2764}️")
    @formatter = Slk::Formatters::ReactionFormatter.new(
      output: @output, emoji_replacer: @emoji, cache_store: @cache
    )
  end

  def test_format_inline_with_resolvable_emoji
    reactions = [
      Slk::Models::Reaction.new(name: 'thumbsup', count: 2, users: %w[U1 U2]),
      Slk::Models::Reaction.new(name: 'heart', count: 1, users: ['U3'])
    ]

    result = @formatter.format_inline(reactions)
    assert_equal " [2 \u{1F44D}, 1 \u{2764}️]", result
  end

  def test_format_inline_falls_back_to_code_when_emoji_unknown
    reactions = [Slk::Models::Reaction.new(name: 'unknown', count: 3, users: [])]

    result = @formatter.format_inline(reactions)
    assert_equal ' [3 :unknown:]', result
  end

  def test_format_inline_with_no_emoji_option
    reactions = [Slk::Models::Reaction.new(name: 'thumbsup', count: 2, users: [])]

    result = @formatter.format_inline(reactions, no_emoji: true)
    assert_equal ' [2 :thumbsup:]', result
  end

  def test_format_summary_uses_yellow_color
    reactions = [
      Slk::Models::Reaction.new(name: 'thumbsup', count: 2, users: []),
      Slk::Models::Reaction.new(name: 'heart', count: 1, users: [])
    ]
    output_color = test_output(color: true)
    formatter = Slk::Formatters::ReactionFormatter.new(
      output: output_color, emoji_replacer: @emoji, cache_store: @cache
    )

    result = formatter.format_summary(reactions)
    assert_match(/\e\[0;33m/, result)
    assert_includes result, "2 \u{1F44D}"
    assert_includes result, "1 \u{2764}️"
  end

  def test_format_summary_without_color
    reactions = [Slk::Models::Reaction.new(name: 'thumbsup', count: 2, users: [])]

    result = @formatter.format_summary(reactions)
    assert_equal "[2 \u{1F44D}]", result
  end

  def test_format_with_timestamps_resolves_users_from_cache
    workspace = mock_workspace('ws1')
    @cache.set_user('ws1', 'U1', 'alice')
    @cache.set_user('ws1', 'U2', 'bob')

    reaction = Slk::Models::Reaction.new(name: 'thumbsup', count: 2, users: %w[U1 U2])
                                    .with_timestamps('U1' => '1700000000.000000', 'U2' => '1700000060.000000')

    lines = @formatter.format_with_timestamps([reaction], workspace)
    assert_equal 1, lines.size
    assert_includes lines.first, "\u{1F44D}"
    assert_includes lines.first, 'alice ('
    assert_includes lines.first, 'bob ('
  end

  def test_format_with_timestamps_uses_user_id_when_no_names_option
    workspace = mock_workspace('ws1')
    @cache.set_user('ws1', 'U1', 'alice')
    reaction = Slk::Models::Reaction.new(name: 'thumbsup', count: 1, users: ['U1'])
                                    .with_timestamps('U1' => '1700000000.000000')

    lines = @formatter.format_with_timestamps([reaction], workspace, no_names: true)
    assert_includes lines.first, 'U1'
    refute_includes lines.first, 'alice'
  end

  def test_format_with_timestamps_uses_user_id_when_not_in_cache
    workspace = mock_workspace('ws1')
    reaction = Slk::Models::Reaction.new(name: 'thumbsup', count: 1, users: ['U99'])
                                    .with_timestamps('U99' => '1700000000.000000')

    lines = @formatter.format_with_timestamps([reaction], workspace)
    assert_includes lines.first, 'U99'
  end

  def test_format_with_timestamps_omits_time_when_no_timestamp
    workspace = mock_workspace('ws1')
    @cache.set_user('ws1', 'U1', 'alice')
    reaction = Slk::Models::Reaction.new(name: 'thumbsup', count: 1, users: ['U1'])

    lines = @formatter.format_with_timestamps([reaction], workspace)
    assert_includes lines.first, 'alice'
    refute_match(/alice \(/, lines.first)
  end

  def test_format_with_timestamps_handles_nil_workspace
    reaction = Slk::Models::Reaction.new(name: 'thumbsup', count: 1, users: ['U1'])
                                    .with_timestamps('U1' => '1700000000.000000')

    lines = @formatter.format_with_timestamps([reaction], nil)
    assert_includes lines.first, 'U1'
  end

  def test_format_with_timestamps_handles_no_emoji_option
    workspace = mock_workspace('ws1')
    reaction = Slk::Models::Reaction.new(name: 'thumbsup', count: 1, users: ['U1'])

    lines = @formatter.format_with_timestamps([reaction], workspace, no_emoji: true)
    assert_includes lines.first, ':thumbsup:'
  end

  def test_format_with_timestamps_returns_empty_for_no_reactions
    workspace = mock_workspace('ws1')
    lines = @formatter.format_with_timestamps([], workspace)
    assert_equal [], lines
  end
end
