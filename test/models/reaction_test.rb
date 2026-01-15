# frozen_string_literal: true

require 'test_helper'

class ReactionTest < Minitest::Test
  def test_basic_reaction
    reaction = SlackCli::Models::Reaction.new(name: 'thumbsup', count: 5)
    assert_equal 'thumbsup', reaction.name
    assert_equal 5, reaction.count
    assert_equal [], reaction.users
  end

  def test_reaction_with_users
    users = %w[U123 U456]
    reaction = SlackCli::Models::Reaction.new(name: 'heart', count: 2, users: users)
    assert_equal users, reaction.users
  end

  def test_emoji_code
    reaction = SlackCli::Models::Reaction.new(name: 'fire')
    assert_equal ':fire:', reaction.emoji_code
  end

  def test_to_s
    reaction = SlackCli::Models::Reaction.new(name: 'star', count: 3)
    assert_equal '3 :star:', reaction.to_s
  end

  def test_from_api
    data = {
      'name' => 'rocket',
      'count' => 7,
      'users' => %w[U111 U222 U333]
    }
    reaction = SlackCli::Models::Reaction.from_api(data)

    assert_equal 'rocket', reaction.name
    assert_equal 7, reaction.count
    assert_equal %w[U111 U222 U333], reaction.users
  end

  def test_from_api_with_missing_fields
    data = { 'name' => 'wave' }
    reaction = SlackCli::Models::Reaction.from_api(data)

    assert_equal 'wave', reaction.name
    assert_equal 0, reaction.count
    assert_equal [], reaction.users
  end

  def test_values_are_frozen
    reaction = SlackCli::Models::Reaction.new(name: 'smile', count: 1, users: %w[U123])
    assert reaction.name.frozen?
    assert reaction.users.frozen?
  end

  def test_default_count_is_zero
    reaction = SlackCli::Models::Reaction.new(name: 'test')
    assert_equal 0, reaction.count
  end

  def test_negative_count_normalized_to_zero
    reaction = SlackCli::Models::Reaction.new(name: 'test', count: -5)
    assert_equal 0, reaction.count
  end

  def test_negative_count_from_api_normalized_to_zero
    data = { 'name' => 'test', 'count' => -10 }
    reaction = SlackCli::Models::Reaction.from_api(data)
    assert_equal 0, reaction.count
  end

  def test_from_api_has_nil_timestamps
    data = { 'name' => 'thumbsup', 'count' => 1, 'users' => %w[U123] }
    reaction = SlackCli::Models::Reaction.from_api(data)
    assert_nil reaction.timestamps
  end

  def test_with_timestamps
    reaction = SlackCli::Models::Reaction.new(name: 'star', count: 2, users: %w[U123 U456])
    timestamps = { 'U123' => '1767996268.000000', 'U456' => '1767996300.000000' }

    enriched = reaction.with_timestamps(timestamps)

    assert_equal 'star', enriched.name
    assert_equal 2, enriched.count
    assert_equal %w[U123 U456], enriched.users
    assert_equal timestamps, enriched.timestamps
  end

  def test_timestamps_predicate_with_nil
    reaction = SlackCli::Models::Reaction.new(name: 'wave', count: 1)
    assert_equal false, reaction.timestamps?
  end

  def test_timestamps_predicate_with_empty_hash
    reaction = SlackCli::Models::Reaction.new(name: 'wave', count: 1, timestamps: {})
    assert_equal false, reaction.timestamps?
  end

  def test_timestamps_predicate_with_timestamps
    timestamps = { 'U123' => '1767996268.000000' }
    reaction = SlackCli::Models::Reaction.new(name: 'wave', count: 1, timestamps: timestamps)
    assert_equal true, reaction.timestamps?
  end

  def test_timestamp_for_user
    timestamps = { 'U123' => '1767996268.000000', 'U456' => '1767996300.000000' }
    reaction = SlackCli::Models::Reaction.new(name: 'fire', count: 2, timestamps: timestamps)

    assert_equal '1767996268.000000', reaction.timestamp_for('U123')
    assert_equal '1767996300.000000', reaction.timestamp_for('U456')
    assert_nil reaction.timestamp_for('U999')
  end

  def test_timestamp_for_without_timestamps
    reaction = SlackCli::Models::Reaction.new(name: 'fire', count: 1)
    assert_nil reaction.timestamp_for('U123')
  end

  def test_timestamps_are_frozen
    timestamps = { 'U123' => '1767996268.000000' }
    reaction = SlackCli::Models::Reaction.new(name: 'heart', count: 1, timestamps: timestamps)
    assert reaction.timestamps.frozen?
  end
end
