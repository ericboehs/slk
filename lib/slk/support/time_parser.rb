# frozen_string_literal: true

require 'time'
require 'date'

module Slk
  module Support
    # Resolves a single clock time ("1:30p", "2026-08-12 8a") to a Unix
    # timestamp. A bare time at or before now rolls to tomorrow; an explicit
    # YYYY-MM-DD date is honoured as given.
    #
    # TimeRangeParser builds the two-sided form on the clock arithmetic here.
    class TimeParser
      TIME = /(\d{1,2})(?::(\d{2}))?\s*([ap]m?)?/i
      PATTERN = /\A(?:(\d{4}-\d{2}-\d{2})\s+)?#{TIME}\z/i

      EXAMPLE = '1:30p or 2026-08-12 8:00'

      # @param now [Time] reference point for rolling bare times forward
      # @return [Integer] Unix timestamp
      def self.parse(input, now: Time.now) = new(now: now).parse(input)

      def self.match?(input) = PATTERN.match?(input.to_s.strip)

      def initialize(now: Time.now)
        @now = now
      end

      def parse(input)
        match = PATTERN.match(input.to_s.strip)
        raise ArgumentError, "Invalid time: #{input}. Use #{EXAMPLE}" unless match

        parts = match.captures[1..3]
        date = match[1] ? parse_date(match[1]) : roll_forward(parts)
        at(date, *parts).to_i
      end

      # The rest of this class is clock arithmetic shared with TimeRangeParser,
      # which needs to place the same parts on dates it works out itself.

      # @param example [String] format hint, so a caller with its own syntax
      #   (TimeRangeParser) does not advertise this class's example
      def parse_date(text, example: EXAMPLE)
        Date.parse(text)
      rescue Date::Error
        raise ArgumentError, "Invalid date: #{text}. Use #{example}"
      end

      def at(date, hour, minute, meridiem)
        hours, minutes = to_24_hour(hour, minute, meridiem)
        time = Time.new(date.year, date.month, date.day, hours, minutes, 0)
        # Ruby silently shifts a local time that DST skips (2:30a on a
        # spring-forward date becomes 3:30a), which would move the window
        # rather than fail. Reject it instead.
        return time if time.hour == hours && time.min == minutes

        raise ArgumentError,
              format('%<clock>s does not exist on %<date>s (clocks skip forward for DST).',
                     clock: format('%<h>02d:%<m>02d', h: hours, m: minutes), date: date)
      end

      # Minutes since midnight, for comparing two times before either has a date.
      def minutes(parts)
        hours, mins = to_24_hour(*parts)
        (hours * 60) + mins
      end

      private

      def roll_forward(parts)
        today = @now.to_date
        at(today, *parts) <= @now ? today + 1 : today
      end

      def to_24_hour(hour, minute, meridiem)
        hours = hour.to_i
        minutes = minute.to_i
        raise ArgumentError, "Invalid minute: #{minute}" if minutes > 59
        return [validate_24_hour(hours), minutes] unless meridiem

        [apply_meridiem(hours, meridiem), minutes]
      end

      def validate_24_hour(hours)
        raise ArgumentError, "Invalid hour: #{hours}" if hours > 23

        hours
      end

      def apply_meridiem(hours, meridiem)
        raise ArgumentError, "Invalid hour for 12-hour time: #{hours}" if hours.zero? || hours > 12

        # 12am is hour 0 and 12pm is hour 12, so fold 12 down before shifting.
        base = hours % 12
        meridiem[0].casecmp?('p') ? base + 12 : base
      end
    end
  end
end
