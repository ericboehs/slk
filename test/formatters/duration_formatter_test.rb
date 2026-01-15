# frozen_string_literal: true

require 'test_helper'

class DurationFormatterTest < Minitest::Test
  def setup
    @formatter = Slk::Formatters::DurationFormatter.new
  end

  def test_format_nil_duration
    assert_equal '', @formatter.format(nil)
  end

  def test_format_zero_duration
    duration = Slk::Models::Duration.new(seconds: 0)
    assert_equal '', @formatter.format(duration)
  end

  def test_format_duration
    duration = Slk::Models::Duration.new(seconds: 3600)
    result = @formatter.format(duration)
    refute_empty result
    assert_includes result, '1h'
  end

  def test_format_remaining_nil
    assert_equal '', @formatter.format_remaining(nil)
  end

  def test_format_remaining_zero
    assert_equal '', @formatter.format_remaining(0)
  end

  def test_format_remaining_negative
    assert_equal '', @formatter.format_remaining(-100)
  end

  def test_format_remaining_positive
    result = @formatter.format_remaining(3661)
    refute_empty result
  end

  def test_format_until_nil
    assert_equal '', @formatter.format_until(nil)
  end

  def test_format_until_zero
    assert_equal '', @formatter.format_until(0)
  end

  def test_format_until_expired
    past_timestamp = Time.now.to_i - 3600
    assert_equal 'expired', @formatter.format_until(past_timestamp)
  end

  def test_format_until_future
    future_timestamp = Time.now.to_i + 3600
    result = @formatter.format_until(future_timestamp)
    refute_empty result
    refute_equal 'expired', result
  end
end
