# frozen_string_literal: true

module SlackCli
  module Commands
    class Dnd < Base
      def execute
        return show_help if show_help?

        case positional_args
        in ["status" | "info"]
          get_status
        in ["on" | "snooze", *rest]
          duration = rest.first ? Models::Duration.parse(rest.first) : Models::Duration.parse("1h")
          set_snooze(duration)
        in ["off" | "end"]
          end_snooze
        in [duration_str] if duration_str.match?(/^\d+[hms]?$/)
          duration = Models::Duration.parse(duration_str)
          set_snooze(duration)
        in []
          get_status
        else
          error("Unknown action: #{positional_args.first}")
          error("Valid actions: status, on, off, or a duration (e.g., 1h)")
          1
        end
      rescue ArgumentError => e
        error("Invalid duration: #{e.message}")
        1
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        <<~HELP
          USAGE: slack dnd [action] [duration]

          Manage Do Not Disturb (snooze) settings.

          ACTIONS:
            (none)          Show current DND status
            status          Show current DND status
            on [duration]   Enable snooze (default: 1h)
            off             Disable snooze
            <duration>      Enable snooze for specified duration

          DURATION FORMAT:
            1h              1 hour
            30m             30 minutes
            1h30m           1 hour 30 minutes

          OPTIONS:
            -w, --workspace     Specify workspace
            --all               Apply to all workspaces
            -q, --quiet         Suppress output
        HELP
      end

      private

      def get_status
        target_workspaces.each do |workspace|
          api = runner.dnd_api(workspace.name)
          data = api.info

          if @options[:all] || target_workspaces.size > 1
            puts "#{output.bold(workspace.name)}:"
          end

          if data["snooze_enabled"]
            remaining = api.snooze_remaining
            if remaining
              puts "  DND: #{output.yellow("snoozing")} (#{remaining} remaining)"
            else
              puts "  DND: #{output.yellow("snoozing")} (expired)"
            end
          else
            puts "  DND: #{output.green("off")}"
          end

          # Show scheduled DND if present
          if data["dnd_enabled"]
            start_time = data["next_dnd_start_ts"]
            end_time = data["next_dnd_end_ts"]
            if start_time && end_time
              start_str = Time.at(start_time).strftime("%H:%M")
              end_str = Time.at(end_time).strftime("%H:%M")
              puts "  Schedule: #{start_str} - #{end_str}"
            end
          end
        end

        0
      end

      def set_snooze(duration)
        target_workspaces.each do |workspace|
          api = runner.dnd_api(workspace.name)
          api.set_snooze(duration)

          success("DND enabled for #{duration} on #{workspace.name}")
        end

        0
      end

      def end_snooze
        target_workspaces.each do |workspace|
          api = runner.dnd_api(workspace.name)
          api.end_snooze

          success("DND disabled on #{workspace.name}")
        end

        0
      end
    end
  end
end
