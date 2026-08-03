# frozen_string_literal: true

require 'time'
require 'date'

module Slk
  module Support
    # Parses a scheduling window ("1:30p-3:30p", "2026-08-04 13:30-15:30")
    # into a [start, end] pair of Unix timestamps.
    #
    # Unlike DateParser, which resolves an input to a point in the past, this
    # always resolves forward: a bare time at or before now rolls to tomorrow,
    # and an end before the start rolls to the next day so overnight windows
    # ("11p-1a") work.
    #
    # Both times share one date, so this cannot express a multi-day window —
    # `slk status schedule --start/--end` is the general form for that.
    class TimeRangeParser
      RANGE_PATTERN = /\A(?:(\d{4}-\d{2}-\d{2})\s+)?#{TimeParser::TIME}\s*-\s*#{TimeParser::TIME}\z/i

      EXAMPLE = '1:30p-3:30p or 2026-08-04 13:30-15:30'

      # Overnight windows are short in practice ("11p-1a", "9p-9a"). Anything
      # longer that only reaches the next day by rollover is almost always a
      # missing am/pm rather than a genuine window.
      MAX_OVERNIGHT_SECONDS = 12 * 3600

      # Hours a bare side can take a borrowed meridiem; "13" is already 24-hour.
      CLOCK_HOURS = (1..12)

      # @param input [String] the range to parse
      # @param now [Time] reference point for rolling bare times forward
      # @return [Array(Integer, Integer)] start and end Unix timestamps
      def self.parse(input, now: Time.now) = new(now: now).parse(input)

      # True when input looks like a time range, used to pick it out of argv.
      def self.match?(input) = RANGE_PATTERN.match?(input.to_s.strip)

      def initialize(now: Time.now)
        @now = now
        @clock = TimeParser.new(now: now)
      end

      def parse(input)
        match = RANGE_PATTERN.match(input.to_s.strip)
        raise ArgumentError, "Invalid time range: #{input}. Use #{EXAMPLE}" unless match

        start_parts, end_parts = infer_meridiems(match)
        date = start_date(match, start_parts)
        start_at = @clock.at(date, *start_parts)
        end_at = end_time(date, start_at, end_parts, input)
        validate_window(input, start_at, end_at)

        [start_at.to_i, end_at.to_i]
      end

      private

      # `match.captures` layout: 0 is the optional date, 1..3 the start time,
      # 4..6 the end. Note the date is `match[1]` in the 1-indexed MatchData form.
      #
      # "1-3p" means 1pm, not 1am: when only one side names a meridiem the
      # other borrows it. The borrow is skipped when it would invert the range
      # ("9-5p" is 9am to 5pm, not 9pm to 5pm).
      def infer_meridiems(match)
        start_parts = match.captures[1..3]
        end_parts = match.captures[4..6]

        if borrowable?(start_parts, end_parts)
          borrowed = with_meridiem(start_parts, end_parts[2])
          return [borrowed, end_parts] if @clock.minutes(borrowed) < @clock.minutes(end_parts)
        elsif borrowable?(end_parts, start_parts)
          borrowed = with_meridiem(end_parts, start_parts[2])
          return [start_parts, borrowed] if @clock.minutes(start_parts) < @clock.minutes(borrowed)
        end

        [start_parts, end_parts]
      end

      def borrowable?(parts, source)
        source[2] && parts[2].nil? && CLOCK_HOURS.cover?(parts[0].to_i)
      end

      def with_meridiem(parts, meridiem) = [parts[0], parts[1], meridiem]

      # An explicit date is honoured as given; a bare time at or before now
      # refers to tomorrow.
      def start_date(match, start_parts)
        return @clock.parse_date(match[1], example: EXAMPLE) if match[1]

        today = @now.to_date
        @clock.at(today, *start_parts) <= @now ? today + 1 : today
      end

      def end_time(date, start_at, end_parts, input)
        end_at = @clock.at(date, *end_parts)
        raise ArgumentError, "Time range #{input} starts and ends at the same time." if end_at == start_at

        # An end before the start means the window crosses midnight.
        end_at < start_at ? @clock.at(date + 1, *end_parts) : end_at
      end

      def validate_window(input, start_at, end_at)
        return if start_at.to_date == end_at.to_date
        return if end_at - start_at <= MAX_OVERNIGHT_SECONDS

        raise ArgumentError,
              "Time range #{input} spans #{((end_at - start_at) / 3600).round} hours. " \
              'Add am/pm (9a-5p), use 24-hour times (9:00-17:00), or --start/--end for a multi-day window.'
      end
    end
  end
end
