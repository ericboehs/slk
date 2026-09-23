# frozen_string_literal: true

require 'test_helper'

class DecimalTimestampTest < Minitest::Test
  def test_parse_keeps_microseconds_that_float_would_collapse
    older = Slk::Support::DecimalTimestamp.parse('9999999999.000001')
    newer = Slk::Support::DecimalTimestamp.parse('9999999999.000002')

    assert_operator older, :<, newer
    assert_equal '9999999999.000001'.to_f, '9999999999.000002'.to_f
  end

  def test_exact_addition_and_decimal_formatting
    assert_equal '1234567890.123455', Slk::Support::DecimalTimestamp.add('1234567890.123456', -0.000001)
    assert_equal '122.999999', Slk::Support::DecimalTimestamp.add('123.000000', -0.000001)
    assert_equal '1900.0', Slk::Support::DecimalTimestamp.add('100.0', 1800)
    assert_equal '123.000000001', Slk::Support::DecimalTimestamp.add('123.000000000', 0.000000001)
    assert_equal '-0.000001', Slk::Support::DecimalTimestamp.add('0.000000', -0.000001)
  end

  def test_rejects_nonterminating_decimal
    assert_raises(ArgumentError) { Slk::Support::DecimalTimestamp.decimal(Rational(1, 3)) }
  end
end
