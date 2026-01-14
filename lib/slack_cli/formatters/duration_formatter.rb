# frozen_string_literal: true

module SlackCli
  module Formatters
    class DurationFormatter
      def format(duration)
        return '' if duration.nil? || duration.zero?

        duration.to_s
      end

      def format_remaining(seconds)
        return '' if seconds.nil? || seconds <= 0

        Models::Duration.new(seconds: seconds).to_s
      end

      def format_until(timestamp)
        return '' if timestamp.nil? || timestamp <= 0

        remaining = timestamp - Time.now.to_i
        return 'expired' if remaining <= 0

        format_remaining(remaining)
      end
    end
  end
end
