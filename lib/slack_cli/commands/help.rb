# frozen_string_literal: true

module SlackCli
  module Commands
    # Displays help information for commands
    class Help < Base
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

      # rubocop:disable Metrics/AbcSize
      def build_commands_section
        <<~COMMANDS
          #{output.bold('COMMANDS:')}
            #{output.cyan('status')}       Get or set your status
            #{output.cyan('presence')}     Get or set your presence (away/active)
            #{output.cyan('dnd')}          Manage Do Not Disturb
            #{output.cyan('messages')}     Read channel or DM messages
            #{output.cyan('unread')}       View and clear unread messages
            #{output.cyan('preset')}       Manage and apply status presets
            #{output.cyan('workspaces')}   Manage Slack workspaces
            #{output.cyan('cache')}        Manage user/channel cache
            #{output.cyan('emoji')}        Download workspace custom emoji
            #{output.cyan('config')}       Configuration and setup
        COMMANDS
      end
      # rubocop:enable Metrics/AbcSize

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
