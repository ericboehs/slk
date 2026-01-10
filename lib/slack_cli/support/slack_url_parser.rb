# frozen_string_literal: true

module SlackCli
  module Support
    class SlackUrlParser
      # Patterns for Slack URLs
      URL_PATTERNS = [
        # https://workspace.slack.com/archives/C123ABC/p1234567890123456
        %r{https?://([^.]+)\.slack\.com/archives/([CG][A-Z0-9]+)/p(\d+)(?:\?thread_ts=(\d+\.\d+))?},
        # https://workspace.slack.com/archives/C123ABC (no message)
        %r{https?://([^.]+)\.slack\.com/archives/([CG][A-Z0-9]+)/?$}
      ].freeze

      Result = Data.define(:workspace, :channel_id, :msg_ts, :thread_ts) do
        def message?
          !msg_ts.nil?
        end

        def thread?
          !thread_ts.nil?
        end

        # For backward compatibility - returns thread_ts if present, otherwise nil
        # This is what you use when you want to fetch replies
        def ts
          thread_ts
        end
      end

      def parse(input)
        return nil unless input.to_s.include?("slack.com")

        URL_PATTERNS.each do |pattern|
          match = input.match(pattern)
          next unless match

          workspace = match[1]
          channel_id = match[2]
          msg_ts = match[3] ? format_ts(match[3]) : nil
          thread_ts = match[4]

          return Result.new(
            workspace: workspace,
            channel_id: channel_id,
            msg_ts: msg_ts,
            thread_ts: thread_ts
          )
        end

        nil
      end

      def slack_url?(input)
        input.to_s.include?("slack.com/archives")
      end

      private

      # Convert Slack URL timestamp format to API format
      # URL: p1234567890123456 -> API: 1234567890.123456
      def format_ts(url_ts)
        return nil unless url_ts

        # Remove 'p' prefix if present
        ts = url_ts.sub(/^p/, "")

        # Insert decimal point
        if ts.length > 6
          "#{ts[0..-7]}.#{ts[-6..]}"
        else
          ts
        end
      end
    end
  end
end
