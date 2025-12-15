# frozen_string_literal: true

module SlackCli
  module Commands
    class Presence < Base
      def execute
        return show_help if show_help?

        case positional_args
        in ["away"]
          set_presence("away")
        in ["auto" | "active"]
          set_presence("auto")
        in []
          get_presence
        else
          error("Unknown presence: #{positional_args.first}")
          error("Valid options: away, auto, active")
          1
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        <<~HELP
          USAGE: slack presence [away|auto|active]

          Get or set your presence status.

          ACTIONS:
            (none)     Show current presence
            away       Set presence to away
            auto       Set presence to auto (active)
            active     Alias for auto

          OPTIONS:
            -w, --workspace     Specify workspace
            --all               Apply to all workspaces
            -q, --quiet         Suppress output
        HELP
      end

      private

      def get_presence
        target_workspaces.each do |workspace|
          data = runner.users_api(workspace.name).get_presence

          if @options[:all] || target_workspaces.size > 1
            puts "#{output.bold(workspace.name)}:"
          end

          presence = data[:presence]
          manual = data[:manual_away]

          status = case [presence, manual]
          in ["away", true]
            output.yellow("away (manual)")
          in ["away", _]
            output.yellow("away")
          in ["active", _]
            output.green("active")
          else
            presence
          end

          puts "  Presence: #{status}"
        end

        0
      end

      def set_presence(presence)
        target_workspaces.each do |workspace|
          runner.users_api(workspace.name).set_presence(presence)

          status_text = presence == "away" ? output.yellow("away") : output.green("active")
          success("Presence set to #{status_text} on #{workspace.name}")
        end

        0
      end
    end
  end
end
