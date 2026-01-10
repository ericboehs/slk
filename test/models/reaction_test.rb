# frozen_string_literal: true

require "test_helper"

class ReactionTest < Minitest::Test
  def test_basic_reaction
    reaction = SlackCli::Models::Reaction.new(name: "thumbsup", count: 5)
    assert_equal "thumbsup", reaction.name
    assert_equal 5, reaction.count
    assert_equal [], reaction.users
  end

  def test_reaction_with_users
    users = %w[U123 U456]
    reaction = SlackCli::Models::Reaction.new(name: "heart", count: 2, users: users)
    assert_equal users, reaction.users
  end

  def test_emoji_code
    reaction = SlackCli::Models::Reaction.new(name: "fire")
    assert_equal ":fire:", reaction.emoji_code
  end

  def test_to_s
    reaction = SlackCli::Models::Reaction.new(name: "star", count: 3)
    assert_equal "3 :star:", reaction.to_s
  end

  def test_from_api
    data = {
      "name" => "rocket",
      "count" => 7,
      "users" => %w[U111 U222 U333]
    }
    reaction = SlackCli::Models::Reaction.from_api(data)

    assert_equal "rocket", reaction.name
    assert_equal 7, reaction.count
    assert_equal %w[U111 U222 U333], reaction.users
  end

  def test_from_api_with_missing_fields
    data = { "name" => "wave" }
    reaction = SlackCli::Models::Reaction.from_api(data)

    assert_equal "wave", reaction.name
    assert_equal 0, reaction.count
    assert_equal [], reaction.users
  end

  def test_values_are_frozen
    reaction = SlackCli::Models::Reaction.new(name: "smile", count: 1, users: %w[U123])
    assert reaction.name.frozen?
    assert reaction.users.frozen?
  end

  def test_default_count_is_zero
    reaction = SlackCli::Models::Reaction.new(name: "test")
    assert_equal 0, reaction.count
  end
end
