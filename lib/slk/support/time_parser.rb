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

      MINUTES_PER_DAY = 24 * 60

      # A bare hour of 0 or 13-23 can only be 24-hour notation, so no am/pm was
      # omitted. Anything in 1..12 is genuinely ambiguous without one.
      CLOCK_HOURS = (1..12)

      # @param now [Time] reference point for rolling bare times forward
      # @return [Integer] Unix timestamp
      def self.parse(input, now: Time.now) = new(now: now).parse(input)

      def initialize(now: Time.now)
        @now = now
      end

      def parse(input)
        match = PATTERN.match(input.to_s.strip)
        raise TimeFormatError, "Invalid time: #{input}. Use #{EXAMPLE}" unless match

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
        raise TimeFormatError, "Invalid date: #{text}. Use #{example}"
      end

      def at(date, *parts)
        hours, minutes = to_24_hour(*parts)
        time = build(date, hours, minutes)
        # Ruby silently shifts a local time that DST skips (2:30a on a
        # spring-forward date becomes 3:30a), which would move the window
        # rather than fail. Reject it instead.
        return time if time.hour == hours && time.min == minutes

        raise TimeFormatError,
              format('%<clock>s does not exist on %<date>s (clocks skip forward for DST).',
                     clock: format('%<h>02d:%<m>02d', h: hours, m: minutes), date: date)
      end

      # Same placement without the existence check, for callers asking a
      # question a nonexistent time still answers. `at` would raise, which for
      # the roll-forward probe would reject "2:30a" outright on a spring-forward
      # date instead of rolling it to the next day, where it does exist.
      def place(date, *parts) = build(date, *to_24_hour(*parts))

      # Minutes since midnight, for comparing two times before either has a date.
      def minutes(parts)
        hours, mins = to_24_hour(*parts)
        (hours * 60) + mins
      end

      # True when these parts could have meant either am or pm — no meridiem
      # given, and an hour small enough that both readings are plausible.
      def ambiguous?(parts) = parts[2].nil? && CLOCK_HOURS.cover?(parts[0].to_i)

      # The opposite: a bare hour too large to be a 12-hour clock reading, so
      # the writer was plainly using 24-hour notation. TimeRangeParser treats
      # one of these as settling how to read the *other* side of a range.
      def twenty_four_hour?(parts) = parts[2].nil? && !CLOCK_HOURS.cover?(parts[0].to_i)

      private

      def build(date, hours, minutes) = Time.new(date.year, date.month, date.day, hours, minutes, 0)

      def roll_forward(parts)
        today = @now.to_date
        place(today, *parts) <= @now ? today + 1 : today
      end

      def to_24_hour(hour, minute, meridiem)
        hours = hour.to_i
        minutes = minute.to_i
        raise TimeFormatError, "Invalid minute: #{minute}" if minutes > 59
        return [validate_24_hour(hours), minutes] unless meridiem

        [apply_meridiem(hours, meridiem), minutes]
      end

      def validate_24_hour(hours)
        raise TimeFormatError, "Invalid hour: #{hours}" if hours > 23

        hours
      end

      def apply_meridiem(hours, meridiem)
        raise TimeFormatError, "Invalid hour for 12-hour time: #{hours}" if hours.zero? || hours > 12

        # 12am is hour 0 and 12pm is hour 12, so fold 12 down before shifting.
        base = hours % 12
        meridiem[0].casecmp?('p') ? base + 12 : base
      end
    end
  end
end
