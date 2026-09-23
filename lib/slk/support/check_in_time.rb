# frozen_string_literal: true

require 'date'
require 'time'

module Slk
  module Support
    # A stateless, exact timestamp for sent-conversation change detection.
    class CheckInTime
      RELATIVE = /\A(\d+)([mhd])\z/i
      CLOCK = /\A(\d{1,2}):(\d{2})\z/
      EPOCH = /\A\d{9,12}(?:\.\d{1,6})?\z/
      ISO = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?\z/

      def self.parse(value, now: Time.now)
        time = case value
               when RELATIVE then relative(Regexp.last_match, now)
               when CLOCK then clock(Regexp.last_match, now)
               when EPOCH then epoch_time(value)
               when ISO then iso_time(value)
               else raise UsageError, 'Invalid --changed-since time. Use H:MM or HH:MM, ISO, epoch, 90m, 2h, or 1d.'
               end
        raise UsageError, '--changed-since must not be in the future.' if time > now

        time
      end

      def self.timestamp(time)
        format('%<seconds>d.%<micros>06d', seconds: time.to_i, micros: time.usec)
      end

      def self.epoch_time(value)
        Time.at(DecimalTimestamp.parse(value))
      rescue ArgumentError
        raise UsageError, "Invalid --changed-since time: #{value.inspect}."
      end

      def self.iso_time(value)
        Date.iso8601(value[0, 10])
        with_seconds = value.sub(/(T\d{2}:\d{2})(?=Z|[+-]\d{2}:\d{2}|\z)/, '\\1:00')
        Time.iso8601(with_seconds)
      rescue ArgumentError
        raise UsageError, "Invalid --changed-since time: #{value.inspect}."
      end

      def self.relative(match, now)
        amount = match[1].to_i
        raise UsageError, '--changed-since duration must be positive.' if amount.zero?

        seconds = { 'm' => 60, 'h' => 3600, 'd' => 86_400 }.fetch(match[2].downcase)
        now - (amount * seconds)
      end

      def self.clock(match, now)
        hour, minute = match.captures.map(&:to_i)
        raise UsageError, 'Invalid --changed-since clock time.' unless hour < 24 && minute < 60

        day = now.to_date
        time = local_clock(day, hour, minute)
        return time if time <= now

        local_clock(day - 1, hour, minute)
      end

      def self.local_clock(day, hour, minute)
        Time.local(day.year, day.month, day.day, hour, minute)
      rescue ArgumentError
        raise UsageError, 'Invalid --changed-since clock time.'
      end
    end
  end
end
