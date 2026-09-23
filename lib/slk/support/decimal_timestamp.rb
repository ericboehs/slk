# frozen_string_literal: true

module Slk
  module Support
    # Exact decimal arithmetic for Slack timestamps without an optional gem.
    module DecimalTimestamp
      def self.parse(value)
        Rational(value.to_s)
      end

      def self.add(timestamp, offset)
        decimal(parse(timestamp) + parse(offset))
      end

      def self.decimal(value)
        twos, remaining = factor(value.denominator, 2)
        fives, remaining = factor(remaining, 5)
        raise ArgumentError, 'Timestamp must have a finite decimal representation' unless remaining == 1

        places = [twos, fives].max
        scaled = value.numerator * ((10**places) / value.denominator)
        format_digits(scaled, places)
      end

      def self.format_digits(scaled, places)
        digits = scaled.abs.to_s.rjust(places + 1, '0')
        sign = scaled.negative? ? '-' : ''
        return "#{sign}#{digits}.0" if places.zero?

        "#{sign}#{digits[0...-places]}.#{digits[-places..]}"
      end
      private_class_method :format_digits

      def self.factor(number, divisor)
        count = 0
        while (number % divisor).zero?
          number /= divisor
          count += 1
        end
        [count, number]
      end
      private_class_method :factor
    end
  end
end
