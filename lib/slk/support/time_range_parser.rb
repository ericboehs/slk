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
    # The start date is written once and the end can only reach the following
    # day, so this cannot express a multi-day window — `slk status schedule
    # --start/--end` is the general form for that.
    class TimeRangeParser
      RANGE_PATTERN = /\A(?:(\d{4}-\d{2}-\d{2})\s+)?#{TimeParser::TIME}\s*-\s*#{TimeParser::TIME}\z/i

      EXAMPLE = '1:30p-3:30p or 2026-08-04 13:30-15:30'

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
        raise TimeFormatError, "Invalid time range: #{input}. Use #{EXAMPLE}" unless match

        start_parts, end_parts = infer_meridiems(match)
        validate_range(input, start_parts, end_parts)

        date = start_date(match, start_parts)
        start_at = @clock.at(date, *start_parts)

        [start_at.to_i, end_time(date, start_at, end_parts).to_i]
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

      def borrowable?(parts, source) = !source[2].nil? && @clock.ambiguous?(parts)

      def with_meridiem(parts, meridiem) = [parts[0], parts[1], meridiem]

      # An explicit date is honoured as given; a bare time at or before now
      # refers to tomorrow.
      def start_date(match, start_parts)
        return @clock.parse_date(match[1], example: EXAMPLE) if match[1]

        today = @now.to_date
        # `place`, not `at`: this only asks "is that time already past today?",
        # and on a spring-forward date `at` would reject a skipped time outright
        # instead of letting it roll to tomorrow, where it exists.
        @clock.place(today, *start_parts) <= @now ? today + 1 : today
      end

      def end_time(date, start_at, end_parts)
        end_at = @clock.at(date, *end_parts)
        # An end before the start means the window crosses midnight.
        end_at < start_at ? @clock.at(date + 1, *end_parts) : end_at
      end

      def validate_range(input, start_parts, end_parts)
        if @clock.minutes(start_parts) == @clock.minutes(end_parts)
          raise TimeFormatError, "Time range #{input} starts and ends at the same time."
        end

        validate_overnight(input, start_parts, end_parts)
      end

      # "9-5" almost always means 9am-5pm, but reads literally as 09:00 to
      # 05:00 the next morning — a 20-hour window nobody asked for.
      #
      # Rejecting *every* ambiguous midnight crossing rather than capping the
      # length is not a shortcut: with both sides bare and in 1..12, the widest
      # such window that fits in 12 hours would need the two to be 12 hours
      # apart, which no pair of 12-hour clock readings can be. They are all too
      # long, so there is no threshold worth writing down.
      #
      # This applies only where a reading had to be guessed. "8p-9a" and
      # "20:00-09:00" are 13-hour nights that say exactly what they mean.
      def validate_overnight(input, start_parts, end_parts)
        return unless ambiguous?(start_parts, end_parts)

        span = overnight_minutes(start_parts, end_parts)
        return unless span

        raise TimeFormatError,
              "Time range #{input} reads as crossing midnight and spans #{format_span(span)}. " \
              'Add am/pm (9a-5p), use 24-hour times (9:00-17:00), or --start/--end for a multi-day window.'
      end

      # Ambiguous only if neither side settles the notation. A single am/pm, or
      # a single hour too large to be 12-hour ("20:00"), fixes how to read both.
      def ambiguous?(start_parts, end_parts)
        @clock.ambiguous?(start_parts) && @clock.ambiguous?(end_parts)
      end

      # Wall-clock minutes from start to end across midnight, or nil when the
      # window stays on one date.
      #
      # Deliberately not `end_at - start_at`: elapsed seconds stretch or shrink
      # by an hour across a DST boundary, so the same text would report a
      # different span depending on the date it happened to land on.
      def overnight_minutes(start_parts, end_parts)
        start_minutes = @clock.minutes(start_parts)
        end_minutes = @clock.minutes(end_parts)
        return nil if end_minutes > start_minutes

        TimeParser::MINUTES_PER_DAY - start_minutes + end_minutes
      end

      # Whole hours read better, but rounding them would report a 12h01m window
      # as "12 hours" against a 12-hour limit.
      def format_span(minutes)
        hours, mins = minutes.divmod(60)
        mins.zero? ? "#{hours} hours" : format('%<h>dh%<m>02dm', h: hours, m: mins)
      end
    end
  end
end
