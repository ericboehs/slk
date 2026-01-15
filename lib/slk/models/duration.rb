# frozen_string_literal: true

module Slk
  module Models
    # Duration unit multipliers (seconds per unit)
    DURATION_UNITS = { 'h' => 3600, 'm' => 60, 's' => 1 }.freeze

    Duration = Data.define(:seconds) do
      class << self
        def parse(input)
          return new(seconds: 0) if input.nil? || input.to_s.strip.empty?
          return new(seconds: input.to_i) if input.to_s.match?(/^\d+$/)

          parse_duration_string(input.to_s.downcase, input)
        end

        def zero = new(seconds: 0)

        def from_minutes(minutes)
          new(seconds: minutes.to_i * 60)
        end

        private

        def parse_duration_string(str, original)
          validate_no_duplicate_units(str, original)
          total = calculate_total_seconds(str)
          raise ArgumentError, "Invalid duration format: #{original}" if total.zero? && !str.match?(/^0/)

          new(seconds: total)
        end

        def validate_no_duplicate_units(str, original)
          DURATION_UNITS.each_key do |unit|
            next unless str.scan(/\d+#{unit}/).length > 1

            raise ArgumentError, "Duplicate '#{unit}' unit in duration: #{original}"
          end
        end

        def calculate_total_seconds(str)
          DURATION_UNITS.sum do |unit, multiplier|
            (match = str.match(/(\d+)#{unit}/)) ? match[1].to_i * multiplier : 0
          end
        end
      end

      def zero? = seconds.zero?

      def to_minutes = (seconds / 60.0).ceil

      def to_expiration
        return 0 if zero?

        Time.now.to_i + seconds
      end

      def to_s
        return '' if zero?

        format_duration
      end

      def +(other)
        Duration.new(seconds: seconds + other.seconds)
      end

      def -(other)
        Duration.new(seconds: [seconds - other.seconds, 0].max)
      end

      private

      def format_duration
        parts = []
        remaining = seconds

        _hours, remaining = extract_unit(remaining, 3600, 'h', parts)
        _minutes, remaining = extract_unit(remaining, 60, 'm', parts)
        parts << "#{remaining}s" if remaining.positive? && parts.empty?

        parts.join
      end

      def extract_unit(remaining, divisor, suffix, parts)
        return [0, remaining] if remaining < divisor

        value = remaining / divisor
        parts << "#{value}#{suffix}"
        [value, remaining % divisor]
      end
    end
  end
end
