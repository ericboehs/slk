# frozen_string_literal: true

require 'test_helper'

class PresetTest < Minitest::Test
  def test_basic_preset
    preset = SlackCli::Models::Preset.new(name: 'lunch', text: 'Out to lunch', emoji: ':fork_and_knife:')

    assert_equal 'lunch', preset.name
    assert_equal 'Out to lunch', preset.text
    assert_equal ':fork_and_knife:', preset.emoji
    assert_equal '0', preset.duration
    assert_equal '', preset.presence
    assert_equal '', preset.dnd
  end

  def test_preset_with_duration
    preset = SlackCli::Models::Preset.new(name: 'meeting', text: 'In a meeting', duration: '1h')
    assert_equal '1h', preset.duration
  end

  def test_preset_with_presence
    preset = SlackCli::Models::Preset.new(name: 'away', presence: 'away')
    assert preset.sets_presence?
    assert_equal 'away', preset.presence
  end

  def test_preset_with_dnd
    preset = SlackCli::Models::Preset.new(name: 'focus', dnd: '2h')
    assert preset.sets_dnd?
    assert_equal '2h', preset.dnd
  end

  def test_sets_presence_returns_false_when_empty
    preset = SlackCli::Models::Preset.new(name: 'test')
    refute preset.sets_presence?
  end

  def test_sets_dnd_returns_false_when_empty
    preset = SlackCli::Models::Preset.new(name: 'test')
    refute preset.sets_dnd?
  end

  def test_clears_status_when_empty_text_and_emoji
    preset = SlackCli::Models::Preset.new(name: 'clear')
    assert preset.clears_status?
  end

  def test_does_not_clear_status_when_text_present
    preset = SlackCli::Models::Preset.new(name: 'test', text: 'Hello')
    refute preset.clears_status?
  end

  def test_does_not_clear_status_when_emoji_present
    preset = SlackCli::Models::Preset.new(name: 'test', emoji: ':wave:')
    refute preset.clears_status?
  end

  def test_from_hash
    data = {
      'text' => 'Working remotely',
      'emoji' => ':house:',
      'duration' => '8h',
      'presence' => 'auto',
      'dnd' => ''
    }
    preset = SlackCli::Models::Preset.from_hash('wfh', data)

    assert_equal 'wfh', preset.name
    assert_equal 'Working remotely', preset.text
    assert_equal ':house:', preset.emoji
    assert_equal '8h', preset.duration
    assert_equal 'auto', preset.presence
    assert_equal '', preset.dnd
  end

  def test_from_hash_with_missing_fields
    preset = SlackCli::Models::Preset.from_hash('empty', {})

    assert_equal 'empty', preset.name
    assert_equal '', preset.text
    assert_equal '', preset.emoji
    assert_equal '0', preset.duration
    assert_equal '', preset.presence
    assert_equal '', preset.dnd
  end

  def test_to_h
    preset = SlackCli::Models::Preset.new(
      name: 'test',
      text: 'Testing',
      emoji: ':test_tube:',
      duration: '30m',
      presence: 'away',
      dnd: '1h'
    )

    expected = {
      'text' => 'Testing',
      'emoji' => ':test_tube:',
      'duration' => '30m',
      'presence' => 'away',
      'dnd' => '1h'
    }

    assert_equal expected, preset.to_h
  end

  def test_to_s_basic
    preset = SlackCli::Models::Preset.new(name: 'lunch', text: 'Lunch', emoji: ':fork_and_knife:')
    assert_equal 'lunch: :fork_and_knife: "Lunch"', preset.to_s
  end

  def test_to_s_with_duration
    preset = SlackCli::Models::Preset.new(name: 'meeting', text: 'Meeting', duration: '1h')
    assert_equal 'meeting: "Meeting" (1h)', preset.to_s
  end

  def test_to_s_with_presence
    preset = SlackCli::Models::Preset.new(name: 'away', presence: 'away')
    assert_equal 'away: [away]', preset.to_s
  end

  def test_to_s_with_dnd
    preset = SlackCli::Models::Preset.new(name: 'focus', dnd: '2h')
    assert_equal 'focus: {dnd: 2h}', preset.to_s
  end

  def test_to_s_with_all_fields
    preset = SlackCli::Models::Preset.new(
      name: 'full',
      text: 'Busy',
      emoji: ':red_circle:',
      duration: '4h',
      presence: 'away',
      dnd: '4h'
    )
    assert_equal 'full: :red_circle: "Busy" (4h) [away] {dnd: 4h}', preset.to_s
  end

  def test_values_are_frozen
    preset = SlackCli::Models::Preset.new(name: 'test', text: 'Testing')
    assert preset.name.frozen?
    assert preset.text.frozen?
    assert preset.emoji.frozen?
    assert preset.duration.frozen?
    assert preset.presence.frozen?
    assert preset.dnd.frozen?
  end

  def test_duration_value_parses_duration
    preset = SlackCli::Models::Preset.new(name: 'test', duration: '2h30m')
    duration = preset.duration_value
    refute_nil duration
    assert_kind_of SlackCli::Models::Duration, duration
  end

  # Validation tests
  def test_raises_when_name_empty
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Preset.new(name: '')
    end
    assert_equal 'preset name cannot be empty', error.message
  end

  def test_raises_when_name_whitespace_only
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Preset.new(name: '   ')
    end
    assert_equal 'preset name cannot be empty', error.message
  end

  def test_strips_whitespace_from_name
    preset = SlackCli::Models::Preset.new(name: '  lunch  ')
    assert_equal 'lunch', preset.name
  end

  def test_raises_when_duration_invalid
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Preset.new(name: 'test', duration: 'invalid')
    end
    assert_match(/invalid duration/i, error.message)
  end

  def test_raises_when_duration_has_duplicate_units
    error = assert_raises(ArgumentError) do
      SlackCli::Models::Preset.new(name: 'test', duration: '1h1h')
    end
    assert_match(/duplicate/i, error.message)
  end

  def test_allows_zero_duration
    preset = SlackCli::Models::Preset.new(name: 'test', duration: '0')
    assert_equal '0', preset.duration
  end

  def test_allows_empty_duration
    preset = SlackCli::Models::Preset.new(name: 'test', duration: '')
    assert_equal '', preset.duration
  end
end
