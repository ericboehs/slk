# frozen_string_literal: true

module Slk
  module Formatters
    # Text for `slk huddles`. A huddle Slack did not attach to a channel is
    # the names plus "channel unknown", not a guessed conversation.
    class HuddleFormatter
      def initialize(output)
        @output = output
      end

      def render(reports, scope: nil)
        reports.each_with_index do |report, index|
          @output.puts if index.positive?
          render_report(report, header: reports.size > 1, scope: reports.one? ? scope : nil)
        end
      end

      private

      def render_report(report, header:, scope:)
        @output.puts(@output.bold(report.workspace)) if header
        @output.puts(summary(report.huddles, scope))
        report.huddles.each { |huddle| render_huddle(huddle) }
      end

      def summary(huddles, scope)
        return "#{with_scope('No active huddles', scope)}." if huddles.empty?

        noun = huddles.one? ? 'huddle' : 'huddles'
        with_scope("#{huddles.size} active #{noun}", scope)
      end

      def with_scope(text, scope)
        scope ? "#{text} on #{scope}" : text
      end

      def render_huddle(huddle)
        @output.puts
        huddle.place ? render_placed(huddle) : render_unplaced(huddle)
      end

      def render_placed(huddle)
        @output.puts(@output.bold(huddle.place))
        huddle.participants.each { |person| @output.puts("  #{person.name}") }
      end

      def render_unplaced(huddle)
        @output.puts(huddle.participants.map(&:name).join(', '))
        @output.puts("  #{@output.gray('channel unknown')}")
      end
    end
  end
end
