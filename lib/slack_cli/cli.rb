# frozen_string_literal: true

module SlackCli
  class CLI
    COMMANDS = {
      "status" => Commands::Status,
      "presence" => Commands::Presence,
      "dnd" => Commands::Dnd,
      "messages" => Commands::Messages,
      "thread" => Commands::Thread,
      "unread" => Commands::Unread,
      "catchup" => Commands::Catchup,
      "preset" => Commands::Preset,
      "workspaces" => Commands::Workspaces,
      "cache" => Commands::Cache,
      "emoji" => Commands::Emoji,
      "config" => Commands::Config,
      "help" => Commands::Help
    }.freeze

    def initialize(argv, output: nil)
      @argv = argv.dup
      @output = output || Formatters::Output.new
    end

    def run
      command_name, *args = @argv

      # Handle version flags
      if command_name.nil? || command_name == "--help" || command_name == "-h"
        return run_command("help", [])
      end

      if command_name == "--version" || command_name == "-V" || command_name == "version"
        @output.puts "slk v#{VERSION}"
        return 0
      end

      # Look up command
      if (command_class = COMMANDS[command_name])
        run_command(command_name, args)
      elsif preset_exists?(command_name)
        # Treat as preset shortcut
        run_command("preset", [command_name] + args)
      else
        @output.error("Unknown command: #{command_name}")
        @output.puts
        @output.puts "Run 'slk help' for available commands."
        1
      end
    rescue ConfigError => e
      @output.error(e.message)
      log_error(e)
      1
    rescue EncryptionError => e
      @output.error("Encryption error: #{e.message}")
      log_error(e)
      1
    rescue ApiError => e
      @output.error("API error: #{e.message}")
      log_error(e)
      1
    rescue Interrupt
      @output.puts
      @output.puts "Interrupted."
      130
    rescue StandardError => e
      @output.error("Unexpected error: #{e.message}")
      log_error(e)
      @output.puts "See error log for details." if @output.verbose
      1
    end

    private

    def run_command(name, args)
      command_class = COMMANDS[name]
      return 1 unless command_class

      verbose = args.include?("-v") || args.include?("--verbose")

      # Create output with verbose flag
      output = Formatters::Output.new(verbose: verbose)
      runner = Runner.new(output: output)

      # Set up API call logging if verbose
      if verbose
        runner.api_client.on_request = ->(method, count) {
          output.debug("[API ##{count}] #{method}")
        }
      end

      command = command_class.new(args, runner: runner)
      result = command.execute

      # Show API call count if verbose
      if verbose && runner.api_client.call_count > 0
        output.debug("Total API calls: #{runner.api_client.call_count}")
      end

      result
    end

    def preset_exists?(name)
      Services::PresetStore.new.exists?(name)
    rescue JSON::ParserError, ConfigError
      false
    end

    def log_error(error)
      Support::ErrorLogger.log(error)
    end
  end
end
