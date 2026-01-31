# frozen_string_literal: true

require_relative '../test_helper'

class SavedItemFormatterTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @mention_replacer = MockMentionReplacer.new
    @text_processor = MockTextProcessor.new
    @formatter = Slk::Formatters::SavedItemFormatter.new(
      output: @output,
      mention_replacer: @mention_replacer,
      text_processor: @text_processor
    )
    @workspace = mock_workspace('test')
  end

  # Status badge tests
  def test_format_status_badge_shows_saved
    item = build_item(state: 'saved')
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, '[saved]'
  end

  def test_format_status_badge_shows_completed
    item = build_item(state: 'completed')
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, '[completed]'
  end

  def test_format_status_badge_shows_in_progress
    item = build_item(state: 'in_progress')
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, '[in_progress]'
  end

  def test_format_status_badge_shows_unknown_state
    item = build_item(state: 'custom_state')
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, '[custom_state]'
  end

  # Due date tests
  def test_format_due_info_shows_future_time
    item = build_item(date_due: Time.now.to_i + 3600) # 1 hour from now
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, 'Due: in 1h'
  end

  def test_format_due_info_shows_past_time_as_ago
    item = build_item(date_due: Time.now.to_i - 7200) # 2 hours ago
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, 'Due: 2h ago'
  end

  def test_format_due_info_not_shown_when_no_due_date
    item = build_item(date_due: nil)
    @formatter.display_item(item, @workspace)

    refute_includes @io.string, 'Due:'
  end

  # Time difference formatting
  def test_format_time_difference_for_seconds
    item = build_item(date_due: Time.now.to_i + 30) # 30 seconds
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, 'in 30s'
  end

  def test_format_time_difference_for_minutes
    item = build_item(date_due: Time.now.to_i + 300) # 5 minutes
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, 'in 5m'
  end

  def test_format_time_difference_for_hours
    item = build_item(date_due: Time.now.to_i + 10_800) # 3 hours
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, 'in 3h'
  end

  def test_format_time_difference_for_days
    item = build_item(date_due: Time.now.to_i + 172_800) # 2 days
    @formatter.display_item(item, @workspace)

    assert_includes @io.string, 'in 2d'
  end

  # Message display tests
  def test_display_message_with_user
    item = build_item
    message = { 'text' => 'Hello world', 'user' => 'U123' }

    @formatter.display_item(item, @workspace, message: message)

    assert_includes @io.string, 'resolved_user:'
    assert_includes @io.string, 'Hello world'
  end

  def test_display_message_with_bot
    item = build_item
    message = { 'text' => 'Bot message', 'bot_id' => 'B123' }

    @formatter.display_item(item, @workspace, message: message)

    assert_includes @io.string, 'Bot:'
    assert_includes @io.string, 'Bot message'
  end

  def test_display_message_with_unknown_author
    item = build_item
    message = { 'text' => 'Mystery message' }

    @formatter.display_item(item, @workspace, message: message)

    assert_includes @io.string, 'Unknown:'
    assert_includes @io.string, 'Mystery message'
  end

  def test_display_message_without_message
    item = build_item
    @formatter.display_item(item, @workspace, message: nil)

    # Should not crash and should show status
    assert_includes @io.string, '[saved]'
    refute_includes @io.string, ':'
  end

  # Truncation tests
  def test_display_truncated_message_respects_width
    item = build_item
    long_text = 'A' * 200
    message = { 'text' => long_text, 'user' => 'U123' }

    @formatter.display_item(item, @workspace, message: message, width: 50, truncate: true)

    output = @io.string
    # Should be truncated (not contain all 200 A's)
    refute_includes output, 'A' * 200
    assert_includes output, '...'
  end

  # Wrapping tests
  def test_display_wrapped_message_handles_multiline
    item = build_item
    message = { 'text' => "Line one\nLine two\nLine three", 'user' => 'U123' }

    @formatter.display_item(item, @workspace, message: message)

    output = @io.string
    assert_includes output, 'Line one'
    assert_includes output, 'Line two'
    assert_includes output, 'Line three'
  end

  def test_display_wrapped_message_wraps_at_width
    item = build_item
    long_text = 'word ' * 50 # Many words to wrap
    message = { 'text' => long_text.strip, 'user' => 'U123' }

    @formatter.display_item(item, @workspace, message: message, width: 40)

    # Should have multiple lines due to wrapping
    lines = @io.string.lines
    assert lines.length > 2, 'Expected wrapped output to have multiple lines'
  end

  # Edge cases
  def test_handles_empty_text_message
    item = build_item
    message = { 'text' => '', 'user' => 'U123' }

    @formatter.display_item(item, @workspace, message: message)

    assert_includes @io.string, '[No text]'
  end

  def test_handles_nil_text_message
    item = build_item
    message = { 'text' => nil, 'user' => 'U123' }

    @formatter.display_item(item, @workspace, message: message)

    assert_includes @io.string, '[No text]'
  end

  private

  def build_item(overrides = {})
    defaults = {
      item_id: 'C123',
      item_type: 'message',
      ts: '1234567890.123456',
      state: 'saved',
      date_created: Time.now.to_i - 86_400,
      date_due: nil,
      date_completed: nil,
      is_archived: false
    }

    Slk::Models::SavedItem.new(**defaults, **overrides)
  end

  # Mock mention replacer
  class MockMentionReplacer
    def replace(text, _workspace)
      text.gsub(/<@(\w+)>/, '@resolved_\1')
    end

    def lookup_user_name(_workspace, _user_id)
      'resolved_user'
    end
  end

  # Mock text processor
  class MockTextProcessor
    def process(text, _workspace, _options = {})
      return '[No text]' if text.to_s.empty?

      text
    end
  end
end
