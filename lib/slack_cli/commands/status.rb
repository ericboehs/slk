# frozen_string_literal: true

module SlackCli
  module Commands
    class Status < Base
      def execute
        return show_help if show_help?

        case positional_args
        in ["clear", *]
          clear_status
        in [text, *rest]
          set_status(text, rest)
        in []
          get_status
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        <<~HELP
          USAGE: slack status [text] [emoji] [duration] [options]

          Get or set your Slack status.

          EXAMPLES:
            slack status                    Show current status
            slack status clear              Clear status
            slack status "Working" :laptop: Set status with emoji
            slack status "Meeting" :calendar: 1h   Set status for 1 hour

          OPTIONS:
            -w, --workspace     Specify workspace
            --all               Apply to all workspaces
            -v, --verbose       Show debug information
            -q, --quiet         Suppress output
        HELP
      end

      private

      def get_status
        target_workspaces.each do |workspace|
          status = runner.users_api(workspace.name).get_status

          if @options[:all] || target_workspaces.size > 1
            puts "#{output.bold(workspace.name)}:"
          end

          if status.empty?
            puts "  (no status set)"
          else
            puts "  #{status}"
          end
        end

        0
      end

      def set_status(text, rest)
        # Parse emoji and duration from rest
        emoji = rest.find { |arg| arg.start_with?(":") && arg.end_with?(":") } || ":speech_balloon:"
        duration_str = rest.find { |arg| arg.match?(/^\d+[hms]?$/) }
        duration = duration_str ? Models::Duration.parse(duration_str) : Models::Duration.zero

        target_workspaces.each do |workspace|
          api = runner.users_api(workspace.name)
          api.set_status(text: text, emoji: emoji, duration: duration)

          success("Status set on #{workspace.name}")
          debug("  Text: #{text}")
          debug("  Emoji: #{emoji}")
          debug("  Duration: #{duration}") unless duration.zero?
        end

        0
      end

      def clear_status
        target_workspaces.each do |workspace|
          api = runner.users_api(workspace.name)
          api.clear_status

          success("Status cleared on #{workspace.name}")
        end

        0
      end
    end
  end
end
