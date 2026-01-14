# frozen_string_literal: true

require "test_helper"

class StatusTest < Minitest::Test
  def test_empty_status
    status = SlackCli::Models::Status.new
    assert status.empty?
    assert_equal "(no status)", status.to_s
  end

  def test_status_with_text_only
    status = SlackCli::Models::Status.new(text: "Working")
    refute status.empty?
    assert_equal "Working", status.to_s
  end

  def test_status_with_emoji_only
    status = SlackCli::Models::Status.new(emoji: ":coffee:")
    refute status.empty?
    assert_equal ":coffee:", status.to_s
  end

  def test_status_with_text_and_emoji
    status = SlackCli::Models::Status.new(text: "Working", emoji: ":computer:")
    refute status.empty?
    assert_equal ":computer: Working", status.to_s
  end

  def test_expires_returns_false_when_no_expiration
    status = SlackCli::Models::Status.new(text: "Working")
    refute status.expires?
  end

  def test_expires_returns_true_when_expiration_set
    status = SlackCli::Models::Status.new(text: "Working", expiration: Time.now.to_i + 3600)
    assert status.expires?
  end

  def test_expired_returns_true_when_past_expiration
    status = SlackCli::Models::Status.new(text: "Working", expiration: Time.now.to_i - 3600)
    assert status.expired?
  end

  def test_expired_returns_false_when_not_expired
    status = SlackCli::Models::Status.new(text: "Working", expiration: Time.now.to_i + 3600)
    refute status.expired?
  end

  def test_expired_returns_false_when_no_expiration
    status = SlackCli::Models::Status.new(text: "Working")
    refute status.expired?
  end

  def test_time_remaining_returns_nil_when_no_expiration
    status = SlackCli::Models::Status.new(text: "Working")
    assert_nil status.time_remaining
  end

  def test_time_remaining_returns_nil_when_expired
    status = SlackCli::Models::Status.new(text: "Working", expiration: Time.now.to_i - 3600)
    assert_nil status.time_remaining
  end

  def test_time_remaining_returns_duration_when_not_expired
    status = SlackCli::Models::Status.new(text: "Working", expiration: Time.now.to_i + 3600)
    remaining = status.time_remaining
    refute_nil remaining
    assert_kind_of SlackCli::Models::Duration, remaining
  end

  def test_expiration_time_returns_nil_when_no_expiration
    status = SlackCli::Models::Status.new(text: "Working")
    assert_nil status.expiration_time
  end

  def test_expiration_time_returns_time_object
    expiration = Time.now.to_i + 3600
    status = SlackCli::Models::Status.new(text: "Working", expiration: expiration)
    assert_kind_of Time, status.expiration_time
    assert_equal expiration, status.expiration_time.to_i
  end

  def test_values_are_frozen
    status = SlackCli::Models::Status.new(text: "Working", emoji: ":coffee:")
    assert status.text.frozen?
    assert status.emoji.frozen?
  end

  def test_handles_nil_values
    status = SlackCli::Models::Status.new(text: nil, emoji: nil, expiration: nil)
    assert status.empty?
    assert_equal 0, status.expiration
  end

  def test_negative_expiration_normalized_to_zero
    status = SlackCli::Models::Status.new(text: "test", expiration: -100)
    assert_equal 0, status.expiration
    refute status.expires?
  end

  def test_negative_expiration_not_considered_expired
    status = SlackCli::Models::Status.new(text: "test", expiration: -100)
    refute status.expired?
  end
end
