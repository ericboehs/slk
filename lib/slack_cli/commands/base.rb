# frozen_string_literal: true

module SlackCli
  module Commands
    class Base
      attr_reader :runner, :options, :positional_args

      def initialize(args, runner:)
        @runner = runner
        @options = default_options
        @positional_args = parse_options(args)
      end

      def execute
        raise NotImplementedError, "Subclass must implement #execute"
      end

      protected

      # Convenience accessors
      def output = runner.output
      def config = runner.config
      def cache_store = runner.cache_store
      def preset_store = runner.preset_store
      def token_store = runner.token_store
      def api_client = runner.api_client

      def default_options
        {
          workspace: nil,
          all: false,
          verbose: false,
          quiet: false,
          json: false
        }
      end

      def parse_options(args)
        remaining = []
        args = args.dup

        while args.any?
          arg = args.shift

          case arg
          when "-w", "--workspace"
            @options[:workspace] = args.shift
          when "--all"
            @options[:all] = true
          when "-v", "--verbose"
            @options[:verbose] = true
          when "-q", "--quiet"
            @options[:quiet] = true
          when "--json"
            @options[:json] = true
          when "-h", "--help"
            @options[:help] = true
          when /^-/
            # Let subclass handle unknown options
            handle_option(arg, args, remaining)
          else
            remaining << arg
          end
        end

        remaining
      end

      # Override in subclass to handle command-specific options
      def handle_option(arg, args, remaining)
        remaining << arg
      end

      # Get workspaces to operate on based on options
      def target_workspaces
        if @options[:all]
          runner.all_workspaces
        elsif @options[:workspace]
          [runner.workspace(@options[:workspace])]
        else
          [runner.workspace]
        end
      end

      # Show help if requested
      def show_help?
        @options[:help]
      end

      def show_help
        output.puts help_text
        0
      end

      def help_text
        "No help available for this command."
      end

      # Output helpers
      def success(message)
        output.success(message) unless @options[:quiet]
      end

      def info(message)
        output.info(message) unless @options[:quiet]
      end

      def warn(message)
        output.warn(message)
      end

      def error(message)
        output.error(message)
      end

      def debug(message)
        output.debug(message) if @options[:verbose]
      end

      def puts(message = "")
        output.puts(message) unless @options[:quiet]
      end

      def print(message)
        output.print(message) unless @options[:quiet]
      end

      # JSON output helper
      def output_json(data)
        output.puts(JSON.pretty_generate(data))
      end
    end
  end
end
