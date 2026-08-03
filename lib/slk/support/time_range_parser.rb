# frozen_string_literal: true

require 'time'
require 'date'

module Slk
  module Support
    # Parses a scheduling window ("1:30p-3:30p", "2026-08-04 13:30-15:30")
    # into a [start, end] pair of Unix timestamps.
    #
    # Unlike DateParser, which resolves an input to a point in the past, this
    # always resolves forward: a bare time that already passed today rolls to
    # tomorrow, and an end at or before the start rolls to the next day so
    # overnight windows ("11p-1a") work.
    class TimeRangeParser
      TIME = /(\d{1,2})(?::(\d{2}))?\s*([ap]m?)?/i
      RANGE_PATTERN = /\A(?:(\d{4}-\d{2}-\d{2})\s+)?#{TIME}\s*-\s*#{TIME}\z/i

      EXAMPLE = '1:30p-3:30p or 2026-08-04 13:30-15:30'

      # @param input [String] the range to parse
      # @param now [Time] reference point for rolling bare times forward
      # @return [Array(Integer, Integer)] start and end Unix timestamps
      def self.parse(input, now: Time.now) = new(now: now).parse(input)

      # True when input looks like a time range, used to pick it out of argv.
      def self.match?(input) = RANGE_PATTERN.match?(input.to_s.strip)

      def initialize(now: Time.now)
        @now = now
      end

      def parse(input)
        match = RANGE_PATTERN.match(input.to_s.strip)
        raise ArgumentError, "Invalid time range: #{input}. Use #{EXAMPLE}" unless match

        date = start_date(match)
        start_at = at(date, *start_parts(match))

        [start_at.to_i, end_time(date, start_at, match).to_i]
      end

      private

      # Capture layout: 0 is the optional date, 1..3 the start time, 4..6 the end.
      def start_parts(match) = match.captures[1..3]
      def end_parts(match) = match.captures[4..6]

      # An explicit date is honoured as given; a bare time that has already
      # passed today refers to tomorrow.
      def start_date(match)
        return Date.parse(match[1]) if match[1]

        today = @now.to_date
        at(today, *start_parts(match)) <= @now ? today + 1 : today
      end

      def end_time(date, start_at, match)
        end_at = at(date, *end_parts(match))
        # An end at or before the start means the window crosses midnight.
        end_at <= start_at ? at(date + 1, *end_parts(match)) : end_at
      end

      def at(date, hour, minute, meridiem)
        hours, minutes = to_24_hour(hour, minute, meridiem)
        Time.new(date.year, date.month, date.day, hours, minutes, 0)
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
