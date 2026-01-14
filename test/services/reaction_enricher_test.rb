# frozen_string_literal: true

require 'test_helper'

class ReactionEnricherTest < Minitest::Test
  # Simple mock for Activity API
  class MockActivityApi
    attr_reader :responses, :test_context

    def initialize(test_context)
      @test_context = test_context
      @responses = []
    end

    def feed(_params)
      @responses.shift || { 'ok' => false }
    end

    def expect_feed(response)
      @responses << response
    end

    def verify
      test_context.assert_equal 0, @responses.length, 'Expected all mocked responses to be consumed'
    end
  end

  def setup
    @activity_api = MockActivityApi.new(self)
    @enricher = SlackCli::Services::ReactionEnricher.new(activity_api: @activity_api)
  end

  def test_enrich_messages_with_empty_array
    result = @enricher.enrich_messages([], 'C123')
    assert_equal [], result
  end

  def test_enrich_messages_with_no_reactions
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'Hello',
      reactions: [],
      channel_id: 'C123'
    )

    # Activity API should be called
    @activity_api.expect_feed({ 'ok' => true, 'items' => [] })

    result = @enricher.enrich_messages([message], 'C123')

    assert_equal 1, result.length
    assert_equal [], result[0].reactions
    @activity_api.verify
  end

  def test_enrich_messages_with_reactions_and_timestamps
    reaction = SlackCli::Models::Reaction.new(
      name: 'thumbsup',
      count: 2,
      users: %w[U456 U789]
    )

    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'Hello',
      reactions: [reaction],
      channel_id: 'C123'
    )

    # Mock activity API response
    activity_response = {
      'ok' => true,
      'items' => [
        {
          'feed_ts' => '1767996268.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '1234567890.123456',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'thumbsup',
              'user' => 'U456'
            }
          }
        },
        {
          'feed_ts' => '1767996300.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '1234567890.123456',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'thumbsup',
              'user' => 'U789'
            }
          }
        }
      ]
    }

    @activity_api.expect_feed(activity_response)

    result = @enricher.enrich_messages([message], 'C123')

    assert_equal 1, result.length
    assert_equal 1, result[0].reactions.length

    enriched_reaction = result[0].reactions[0]
    assert enriched_reaction.has_timestamps?
    assert_equal '1767996268.000000', enriched_reaction.timestamp_for('U456')
    assert_equal '1767996300.000000', enriched_reaction.timestamp_for('U789')

    @activity_api.verify
  end

  def test_enrich_messages_with_partial_timestamps
    # Some users have timestamps, some don't
    reaction = SlackCli::Models::Reaction.new(
      name: 'heart',
      count: 3,
      users: %w[U111 U222 U333]
    )

    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'Hello',
      reactions: [reaction],
      channel_id: 'C123'
    )

    # Only have timestamp for U111
    activity_response = {
      'ok' => true,
      'items' => [
        {
          'feed_ts' => '1767996268.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '1234567890.123456',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'heart',
              'user' => 'U111'
            }
          }
        }
      ]
    }

    @activity_api.expect_feed(activity_response)

    result = @enricher.enrich_messages([message], 'C123')

    enriched_reaction = result[0].reactions[0]
    assert enriched_reaction.has_timestamps?
    assert_equal '1767996268.000000', enriched_reaction.timestamp_for('U111')
    assert_nil enriched_reaction.timestamp_for('U222')
    assert_nil enriched_reaction.timestamp_for('U333')

    @activity_api.verify
  end

  def test_enrich_messages_filters_by_message_timestamp
    # Activity includes reactions for messages we don't care about
    reaction = SlackCli::Models::Reaction.new(
      name: 'fire',
      count: 1,
      users: %w[U456]
    )

    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'Hello',
      reactions: [reaction],
      channel_id: 'C123'
    )

    activity_response = {
      'ok' => true,
      'items' => [
        # This one should match
        {
          'feed_ts' => '1767996268.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '1234567890.123456',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'fire',
              'user' => 'U456'
            }
          }
        },
        # This one should be filtered out (different message)
        {
          'feed_ts' => '1767996300.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '9999999999.999999',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'fire',
              'user' => 'U789'
            }
          }
        }
      ]
    }

    @activity_api.expect_feed(activity_response)

    result = @enricher.enrich_messages([message], 'C123')

    enriched_reaction = result[0].reactions[0]
    assert enriched_reaction.has_timestamps?
    assert_equal '1767996268.000000', enriched_reaction.timestamp_for('U456')

    @activity_api.verify
  end

  def test_enrich_messages_with_multiple_messages
    reaction1 = SlackCli::Models::Reaction.new(
      name: 'thumbsup',
      count: 1,
      users: %w[U456]
    )

    reaction2 = SlackCli::Models::Reaction.new(
      name: 'heart',
      count: 1,
      users: %w[U789]
    )

    message1 = SlackCli::Models::Message.new(
      ts: '1234567890.111111',
      user_id: 'U123',
      text: 'First',
      reactions: [reaction1],
      channel_id: 'C123'
    )

    message2 = SlackCli::Models::Message.new(
      ts: '1234567890.222222',
      user_id: 'U123',
      text: 'Second',
      reactions: [reaction2],
      channel_id: 'C123'
    )

    activity_response = {
      'ok' => true,
      'items' => [
        {
          'feed_ts' => '1767996268.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '1234567890.111111',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'thumbsup',
              'user' => 'U456'
            }
          }
        },
        {
          'feed_ts' => '1767996300.000000',
          'item' => {
            'type' => 'message_reaction',
            'message' => {
              'ts' => '1234567890.222222',
              'channel' => 'C123'
            },
            'reaction' => {
              'name' => 'heart',
              'user' => 'U789'
            }
          }
        }
      ]
    }

    @activity_api.expect_feed(activity_response)

    result = @enricher.enrich_messages([message1, message2], 'C123')

    assert_equal 2, result.length
    assert_equal '1767996268.000000', result[0].reactions[0].timestamp_for('U456')
    assert_equal '1767996300.000000', result[1].reactions[0].timestamp_for('U789')

    @activity_api.verify
  end

  def test_enrich_messages_handles_api_failure
    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'Hello',
      reactions: [],
      channel_id: 'C123'
    )

    # API returns error
    @activity_api.expect_feed({ 'ok' => false, 'error' => 'some_error' })

    result = @enricher.enrich_messages([message], 'C123')

    # Should return original messages unchanged
    assert_equal 1, result.length
    assert_equal [], result[0].reactions

    @activity_api.verify
  end

  def test_enrich_messages_preserves_reactions_without_timestamps
    # Reactions that don't have any matching timestamps should remain unchanged
    reaction = SlackCli::Models::Reaction.new(
      name: 'wave',
      count: 1,
      users: %w[U999]
    )

    message = SlackCli::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'Hello',
      reactions: [reaction],
      channel_id: 'C123'
    )

    # Activity has no matching reactions
    @activity_api.expect_feed({ 'ok' => true, 'items' => [] })

    result = @enricher.enrich_messages([message], 'C123')

    # Reaction should be preserved but without timestamps
    enriched_reaction = result[0].reactions[0]
    refute enriched_reaction.has_timestamps?
    assert_equal 'wave', enriched_reaction.name
    assert_equal 1, enriched_reaction.count

    @activity_api.verify
  end
end
