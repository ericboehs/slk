# frozen_string_literal: true

require 'test_helper'

class MessageTest < Minitest::Test
  def test_from_api_with_simple_text
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123',
      'text' => 'Hello world'
    }

    message = SlackCli::Models::Message.from_api(data)

    assert_equal 'Hello world', message.text
    assert_equal 'U123', message.user_id
  end

  def test_from_api_extracts_section_block_text
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123',
      'text' => '',
      'blocks' => [
        {
          'type' => 'section',
          'text' => { 'type' => 'mrkdwn', 'text' => 'Block Kit section text' }
        }
      ]
    }

    message = SlackCli::Models::Message.from_api(data)

    assert_equal 'Block Kit section text', message.text
  end

  def test_from_api_extracts_rich_text_block
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123',
      'text' => '',
      'blocks' => [
        {
          'type' => 'rich_text',
          'elements' => [
            {
              'type' => 'rich_text_section',
              'elements' => [
                { 'type' => 'text', 'text' => 'Rich text ' },
                { 'type' => 'text', 'text' => 'content' }
              ]
            }
          ]
        }
      ]
    }

    message = SlackCli::Models::Message.from_api(data)

    assert_equal 'Rich text content', message.text
  end

  def test_from_api_prefers_text_when_long_enough
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123',
      'text' => 'This is a sufficiently long message text that should be used',
      'blocks' => [
        {
          'type' => 'section',
          'text' => { 'type' => 'mrkdwn', 'text' => 'Block text that should be ignored' }
        }
      ]
    }

    message = SlackCli::Models::Message.from_api(data)

    assert_equal 'This is a sufficiently long message text that should be used', message.text
  end

  def test_from_api_uses_blocks_when_text_is_short
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123',
      'text' => 'Short',
      'blocks' => [
        {
          'type' => 'section',
          'text' => { 'type' => 'mrkdwn', 'text' => 'Longer block text with more content' }
        }
      ]
    }

    message = SlackCli::Models::Message.from_api(data)

    assert_equal 'Longer block text with more content', message.text
  end

  def test_has_thread_returns_true_when_reply_count_positive
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      reply_count: 5
    )

    assert message.has_thread?
  end

  def test_has_thread_returns_false_when_reply_count_zero
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      reply_count: 0
    )

    refute message.has_thread?
  end

  def test_is_reply_when_thread_ts_differs_from_ts
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      thread_ts: '1234567890.000000'
    )

    assert message.is_reply?
  end

  def test_is_not_reply_when_thread_ts_equals_ts
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      thread_ts: '1234567890.123456'
    )

    refute message.is_reply?
  end

  def test_bot_detection
    bot_message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'B123',
      subtype: nil
    )

    assert bot_message.bot?

    bot_subtype_message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      subtype: 'bot_message'
    )

    assert bot_subtype_message.bot?

    regular_message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      subtype: nil
    )

    refute regular_message.bot?
  end

  def test_embedded_username_from_user_profile
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      user_profile: { 'display_name' => 'johnd', 'real_name' => 'John Doe' }
    )

    assert_equal 'johnd', message.embedded_username
  end

  def test_embedded_username_falls_back_to_real_name
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      user_profile: { 'display_name' => '', 'real_name' => 'John Doe' }
    )

    assert_equal 'John Doe', message.embedded_username
  end

  def test_embedded_username_from_bot_profile
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'B123',
      bot_profile: { 'name' => 'MyBot' }
    )

    assert_equal 'MyBot', message.embedded_username
  end

  def test_has_blocks_returns_true_when_blocks_present
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      blocks: [
        { 'type' => 'section', 'text' => { 'text' => 'Block content' } }
      ]
    )

    assert message.has_blocks?
  end

  def test_has_blocks_returns_false_when_blocks_empty
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      blocks: []
    )

    refute message.has_blocks?
  end

  def test_has_blocks_returns_false_when_blocks_default
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123'
    )

    refute message.has_blocks?
  end

  def test_blocks_field_preserved_in_message
    blocks = [
      { 'type' => 'section', 'text' => { 'text' => 'First block' } },
      { 'type' => 'section', 'text' => { 'text' => 'Second block' } }
    ]

    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      blocks: blocks
    )

    assert_equal 2, message.blocks.size
    assert_equal 'section', message.blocks[0]['type']
  end

  def test_from_api_preserves_blocks
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123',
      'text' => 'Some message text',
      'blocks' => [
        { 'type' => 'section', 'text' => { 'type' => 'mrkdwn', 'text' => 'Block content' } }
      ]
    }

    message = SlackCli::Models::Message.from_api(data)

    assert message.has_blocks?
    assert_equal 1, message.blocks.size
    assert_equal 'section', message.blocks[0]['type']
  end

  def test_has_files_returns_true_when_files_present
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      files: [{ 'id' => 'F123', 'name' => 'file.txt' }]
    )

    assert message.has_files?
  end

  def test_has_files_returns_false_when_files_empty
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      files: []
    )

    refute message.has_files?
  end

  def test_has_reactions_returns_true_when_reactions_present
    reaction = SlackCli::Models::Reaction.new(name: 'thumbsup', count: 3, users: [])
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      reactions: [reaction]
    )

    assert message.has_reactions?
  end

  def test_has_reactions_returns_false_when_reactions_empty
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      reactions: []
    )

    refute message.has_reactions?
  end
end
