# frozen_string_literal: true

module SlackCli
  class CLI
    COMMANDS = {
      "status" => Commands::Status,
      "presence" => Commands::Presence,
      "dnd" => Commands::Dnd,
      "messages" => Commands::Messages,
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

      runner = Runner.new(output: @output)
      command = command_class.new(args, runner: runner)
      command.execute
    end

    def preset_exists?(name)
      Services::PresetStore.new.exists?(name)
    rescue StandardError
      false
    end

    def log_error(error)
      paths = Support::XdgPaths.new
      paths.ensure_cache_dir

      log_file = paths.cache_file("error.log")
      File.open(log_file, "a") do |f|
        f.puts "#{Time.now.iso8601} - #{error.class}: #{error.message}"
        if error.backtrace
          f.puts error.backtrace.first(10).map { |line| "  #{line}" }.join("\n")
        end
        f.puts
      end
    end
  end
end
