# frozen_string_literal: true

module SlackCli
  module Models
    Duration = Data.define(:seconds) do
      class << self
        def parse(input)
          return new(seconds: 0) if input.nil? || input.to_s.strip.empty?
          return new(seconds: input.to_i) if input.to_s.match?(/^\d+$/)

          total = 0
          str = input.to_s.downcase

          if (match = str.match(/(\d+)h/))
            total += match[1].to_i * 3600
          end
          if (match = str.match(/(\d+)m/))
            total += match[1].to_i * 60
          end
          if (match = str.match(/(\d+)s/))
            total += match[1].to_i
          end

          raise ArgumentError, "Invalid duration format: #{input}" if total.zero? && !str.match?(/^0/)

          new(seconds: total)
        end

        def zero = new(seconds: 0)

        def from_minutes(minutes)
          new(seconds: minutes.to_i * 60)
        end
      end

      def zero? = seconds.zero?

      def to_minutes = (seconds / 60.0).ceil

      def to_expiration
        return 0 if zero?

        Time.now.to_i + seconds
      end

      def to_s
        return "" if zero?

        parts = []
        remaining = seconds

        if remaining >= 3600
          hours = remaining / 3600
          parts << "#{hours}h"
          remaining %= 3600
        end

        if remaining >= 60
          minutes = remaining / 60
          parts << "#{minutes}m"
          remaining %= 60
        end

        if remaining > 0 && parts.empty?
          parts << "#{remaining}s"
        end

        parts.join
      end

      def +(other)
        Duration.new(seconds: seconds + other.seconds)
      end

      def -(other)
        Duration.new(seconds: [seconds - other.seconds, 0].max)
      end
    end
  end
end
