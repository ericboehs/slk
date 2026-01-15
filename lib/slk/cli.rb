# frozen_string_literal: true

module Slk
  # Command-line interface entry point that dispatches to commands
  # rubocop:disable Metrics/ClassLength
  class CLI
    COMMANDS = {
      'status' => Commands::Status,
      'presence' => Commands::Presence,
      'dnd' => Commands::Dnd,
      'messages' => Commands::Messages,
      'thread' => Commands::Thread,
      'unread' => Commands::Unread,
      'catchup' => Commands::Catchup,
      'activity' => Commands::Activity,
      'preset' => Commands::Preset,
      'workspaces' => Commands::Workspaces,
      'cache' => Commands::Cache,
      'emoji' => Commands::Emoji,
      'config' => Commands::Config,
      'help' => Commands::Help
    }.freeze

    def initialize(argv, output: nil)
      @argv = argv.dup
      @output = output || Formatters::Output.new
    end

    def run
      command_name, *args = @argv

      return show_help if help_requested?(command_name)
      return show_version if version_requested?(command_name)

      dispatch_command(command_name, args)
    rescue Interrupt
      handle_interrupt
    rescue StandardError => e
      handle_error(e)
    end

    private

    def help_requested?(command_name)
      command_name.nil? || command_name == '--help' || command_name == '-h'
    end

    def version_requested?(command_name)
      ['--version', '-V', 'version'].include?(command_name)
    end

    def show_help
      run_command('help', [])
    end

    def show_version
      @output.puts "slk v#{VERSION}"
      0
    end

    def dispatch_command(command_name, args)
      if COMMANDS[command_name]
        run_command(command_name, args)
      elsif preset_exists?(command_name)
        run_command('preset', [command_name] + args)
      else
        show_unknown_command(command_name)
      end
    rescue ConfigError, EncryptionError, ApiError => e
      handle_known_error(e)
    end

    def show_unknown_command(command_name)
      @output.error("Unknown command: #{command_name}")
      @output.puts
      @output.puts "Run 'slk help' for available commands."
      1
    end

    def handle_known_error(error)
      label = error_label(error)
      @output.error(label ? "#{label}: #{error.message}" : error.message)
      log_error(error)
      1
    end

    def error_label(error)
      case error
      when EncryptionError then 'Encryption error'
      when ApiError then 'API error'
      end
    end

    def handle_interrupt
      @output.puts
      @output.puts 'Interrupted.'
      130
    end

    def handle_error(error)
      @output.error("Unexpected error: #{error.message}")
      log_path = log_error(error)
      @output.puts "Details logged to: #{log_path}" if log_path
      1
    end

    def run_command(name, args)
      command_class = COMMANDS[name]
      return 1 unless command_class

      runner = build_runner(args)
      execute_command(command_class, args, runner)
    ensure
      runner&.api_client&.close
    end

    def build_runner(args)
      verbose = verbose_mode?(args)
      very_verbose = args.include?('-vv') || args.include?('--very-verbose')
      output = @output || Formatters::Output.new(verbose: verbose)
      runner = Runner.new(output: output)
      setup_verbose_logging(runner, output) if verbose
      setup_very_verbose_logging(runner, output) if very_verbose
      runner
    end

    def setup_verbose_logging(runner, output)
      runner.api_client.on_request = lambda { |method, count|
        output.debug("[API ##{count}] #{method}")
      }
    end

    def setup_very_verbose_logging(runner, output)
      runner.api_client.on_response = lambda { |method, code, headers|
        next if headers.empty?

        parts = headers.map { |k, v| "#{k.sub('X-RateLimit-', '')}=#{v}" }
        output.debug("  #{method} #{code}: #{parts.join(', ')}")
      }
    end

    def execute_command(command_class, args, runner)
      command = command_class.new(args, runner: runner)
      result = command.execute
      log_api_call_count(runner) if verbose_mode?(args)
      result
    end

    def verbose_mode?(args)
      args.include?('-v') || args.include?('--verbose') ||
        args.include?('-vv') || args.include?('--very-verbose')
    end

    def log_api_call_count(runner)
      return unless runner.api_client.call_count.positive?

      runner.output.debug("Total API calls: #{runner.api_client.call_count}")
    end

    def preset_exists?(name)
      Services::PresetStore.new.exists?(name)
    end

    def log_error(error)
      Support::ErrorLogger.log(error)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
