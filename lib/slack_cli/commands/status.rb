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

      def default_options
        super.merge(presence: nil, dnd: nil)
      end

      def handle_option(arg, args, remaining)
        case arg
        when "-p", "--presence"
          @options[:presence] = args.shift
        when "-d", "--dnd"
          @options[:dnd] = args.shift
        else
          remaining << arg
        end
      end

      def help_text
        <<~HELP
          USAGE: slk status [text] [emoji] [duration] [options]

          Get or set your Slack status.

          EXAMPLES:
            slk status                         Show current status
            slk status clear                   Clear status
            slk status "Working" :laptop:      Set status with emoji
            slk status "Meeting" :calendar: 1h Set status for 1 hour
            slk status "Focus" :headphones: 2h -p away -d 2h

          OPTIONS:
            -p, --presence VALUE  Also set presence (away/auto/active)
            -d, --dnd DURATION    Also set DND (or 'off')
            -w, --workspace       Specify workspace
            --all                 Apply to all workspaces
            -v, --verbose         Show debug information
            -q, --quiet           Suppress output
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

          # Handle combo options
          apply_presence(workspace) if @options[:presence]
          apply_dnd(workspace) if @options[:dnd]
        end

        0
      end

      def apply_presence(workspace)
        value = @options[:presence]
        value = "auto" if value == "active"

        api = runner.users_api(workspace.name)
        api.set_presence(value)
        success("Presence set to #{value} on #{workspace.name}")
      end

      def apply_dnd(workspace)
        value = @options[:dnd]
        dnd_api = runner.dnd_api(workspace.name)

        if value == "off"
          dnd_api.end_snooze
          success("DND disabled on #{workspace.name}")
        else
          duration = Models::Duration.parse(value)
          dnd_api.set_snooze(duration.to_minutes)
          success("DND enabled for #{value} on #{workspace.name}")
        end
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
