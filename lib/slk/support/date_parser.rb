# frozen_string_literal: true

require 'time'

module Slk
  module Support
    # Parses date strings into timestamps for Slack API queries
    # Supports duration formats (1d, 7d, 1w, 1m) and ISO dates (YYYY-MM-DD)
    class DateParser
      DURATION_PATTERN = /\A(\d+)([dwm])\z/i
      ISO_DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

      # Parse a date string and return a Unix timestamp
      # @param input [String] duration (1d, 7d, 1w, 1m) or ISO date (YYYY-MM-DD)
      # @return [Integer] Unix timestamp
      # @raise [ArgumentError] if format is invalid
      def self.parse(input)
        new.parse(input)
      end

      # Parse a date string and return a Slack-formatted timestamp (with microseconds)
      # @param input [String] duration or ISO date
      # @return [String] Slack timestamp like "1234567890.000000"
      def self.to_slack_timestamp(input)
        "#{parse(input)}.000000"
      end

      def parse(input)
        input = input.to_s.strip

        case input
        when DURATION_PATTERN
          parse_duration(input)
        when ISO_DATE_PATTERN
          parse_iso_date(input)
        else
          raise ArgumentError, "Invalid date format: #{input}. Use duration (1d, 7d, 1w, 1m) or ISO date (YYYY-MM-DD)"
        end
      end

      private

      def parse_duration(input)
        match = input.match(DURATION_PATTERN)
        amount = match[1].to_i
        unit = match[2].downcase

        seconds_ago = case unit
                      when 'd' then amount * 86_400        # days
                      when 'w' then amount * 7 * 86_400    # weeks
                      when 'm' then amount * 30 * 86_400   # months (approximate)
                      end

        Time.now.to_i - seconds_ago
      end

      def parse_iso_date(input)
        Time.parse("#{input} 00:00:00").to_i
      rescue ArgumentError
        raise ArgumentError, "Invalid ISO date: #{input}"
      end
    end
  end
end
