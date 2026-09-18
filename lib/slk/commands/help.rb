# frozen_string_literal: true

module Slk
  module Commands
    # Displays help information for commands
    class Help < Base
      # Names are padded to the longest one rather than by hand, so adding a
      # command cannot quietly break the column for every line below it.
      COMMAND_SUMMARIES = [
        ['status', 'Get or set your status'],
        ['presence', 'Get or set your presence (away/active)'],
        ['dnd', 'Manage Do Not Disturb'],
        ['messages', 'Read channel or DM messages'],
        ['search', 'Search messages across channels'],
        ['unread', 'View and clear unread messages'],
        ['activity', 'Show activity feed (reactions, mentions, threads)'],
        ['later', 'Show saved "Later" items'],
        ['who', 'Show a user profile'],
        ['deactivations', 'Show who left the workspace, and when'],
        ['preset', 'Manage and apply status presets'],
        ['workspaces', 'Manage Slack workspaces'],
        ['cache', 'Manage user/channel cache'],
        ['emoji', 'Download workspace custom emoji'],
        ['config', 'Configuration and setup']
      ].freeze

      def execute
        topic = positional_args.first

        if topic
          show_command_help(topic)
        else
          show_general_help
        end

        0
      end

      private

      def show_general_help
        puts build_header
        puts build_commands_section
        puts build_options_section
        puts build_examples_section
        puts "Run #{output.cyan('slk <command> --help')} for command-specific help."
      end

      def build_header
        <<~HEADER
          #{output.bold('slk')} - Slack CLI v#{VERSION}

          #{output.bold('USAGE:')}
            slk <command> [options]
        HEADER
      end

      def build_commands_section
        width = COMMAND_SUMMARIES.map { |name, _| name.length }.max + 2
        rows = COMMAND_SUMMARIES.map do |name, summary|
          "  #{output.cyan(name)}#{' ' * (width - name.length)}#{summary}"
        end
        "#{output.bold('COMMANDS:')}\n#{rows.join("\n")}\n"
      end

      def build_options_section
        <<~OPTIONS
          #{output.bold('GLOBAL OPTIONS:')}
            -w, --workspace NAME   Use specific workspace
            --all                  Apply to all workspaces
            -v, --verbose          Show debug output
            -q, --quiet            Suppress output
            --json                 Output as JSON (where supported)
            -h, --help             Show help
        OPTIONS
      end

      def build_examples_section
        <<~EXAMPLES
          #{output.bold('EXAMPLES:')}
            slk status                       Show current status
            slk status "Working" :laptop:    Set status
            slk status clear                 Clear status
            slk status schedule "Vet" 1p-3p  Schedule a status (am/pm or 24h)
            slk dnd 1h                       Enable DND for 1 hour
            slk messages #general            Read channel messages
            slk preset meeting               Apply preset
        EXAMPLES
      end

      def show_command_help(topic)
        command_class = CLI::COMMANDS[topic]

        if command_class
          # Create instance just to get help text
          # Call --help directly since help_text is protected
          runner_stub = Runner.new(output: output)
          cmd = command_class.new(['--help'], runner: runner_stub)
          cmd.execute
        else
          error("Unknown command: #{topic}")
          puts
          puts "Available commands: #{CLI::COMMANDS.keys.join(', ')}"
        end
      end
    end
  end
end
