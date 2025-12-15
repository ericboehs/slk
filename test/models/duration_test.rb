# frozen_string_literal: true

require "test_helper"

class DurationTest < Minitest::Test
  def test_parse_hours
    duration = SlackCli::Models::Duration.parse("2h")
    assert_equal 7200, duration.seconds
  end

  def test_parse_minutes
    duration = SlackCli::Models::Duration.parse("30m")
    assert_equal 1800, duration.seconds
  end

  def test_parse_seconds
    duration = SlackCli::Models::Duration.parse("45s")
    assert_equal 45, duration.seconds
  end

  def test_parse_combined
    duration = SlackCli::Models::Duration.parse("1h30m")
    assert_equal 5400, duration.seconds
  end

  def test_parse_raw_seconds
    duration = SlackCli::Models::Duration.parse("3600")
    assert_equal 3600, duration.seconds
  end

  def test_parse_nil
    duration = SlackCli::Models::Duration.parse(nil)
    assert_equal 0, duration.seconds
  end

  def test_parse_empty
    duration = SlackCli::Models::Duration.parse("")
    assert_equal 0, duration.seconds
  end

  def test_zero
    duration = SlackCli::Models::Duration.zero
    assert duration.zero?
    assert_equal 0, duration.seconds
  end

  def test_to_minutes
    duration = SlackCli::Models::Duration.parse("90s")
    assert_equal 2, duration.to_minutes
  end

  def test_to_s_hours
    duration = SlackCli::Models::Duration.new(seconds: 7200)
    assert_equal "2h", duration.to_s
  end

  def test_to_s_combined
    duration = SlackCli::Models::Duration.new(seconds: 5400)
    assert_equal "1h30m", duration.to_s
  end

  def test_to_s_zero
    duration = SlackCli::Models::Duration.zero
    assert_equal "", duration.to_s
  end

  def test_to_expiration_returns_future_timestamp
    duration = SlackCli::Models::Duration.parse("1h")
    expiration = duration.to_expiration

    assert_in_delta Time.now.to_i + 3600, expiration, 2
  end

  def test_to_expiration_zero_returns_zero
    duration = SlackCli::Models::Duration.zero
    assert_equal 0, duration.to_expiration
  end

  def test_addition
    a = SlackCli::Models::Duration.parse("1h")
    b = SlackCli::Models::Duration.parse("30m")
    result = a + b

    assert_equal 5400, result.seconds
  end

  def test_subtraction
    a = SlackCli::Models::Duration.parse("1h")
    b = SlackCli::Models::Duration.parse("30m")
    result = a - b

    assert_equal 1800, result.seconds
  end

  def test_from_minutes
    duration = SlackCli::Models::Duration.from_minutes(60)
    assert_equal 3600, duration.seconds
  end
end
