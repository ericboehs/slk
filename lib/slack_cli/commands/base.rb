# frozen_string_literal: true

module SlackCli
  module Commands
    # Base class for all CLI commands with option parsing and output helpers
    # rubocop:disable Metrics/ClassLength
    class Base
      attr_reader :runner, :options, :positional_args

      def initialize(args, runner:)
        @runner = runner
        @options = default_options
        @positional_args = parse_options(args)
      end

      def execute
        raise NotImplementedError, 'Subclass must implement #execute'
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
        base_options.merge(formatting_options)
      end

      def base_options
        { workspace: nil, all: false, verbose: false, quiet: false, json: false, width: default_width }
      end

      def formatting_options
        { no_emoji: false, no_reactions: false, no_names: false, reaction_names: false, reaction_timestamps: false }
      end

      # Default wrap width: 72 for interactive terminals, nil (no wrap) otherwise
      def default_width
        $stdout.tty? ? 72 : nil
      end

      def parse_options(args)
        remaining = []
        args = args.dup
        @unknown_options = []

        while args.any?
          arg = args.shift
          next remaining << arg unless arg.start_with?('-')

          parse_single_option(arg, args, remaining)
        end

        remaining
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      def parse_single_option(arg, args, remaining)
        case arg
        when '-w', '--workspace' then @options[:workspace] = args.shift
        when '--width' then parse_width_option(args)
        when '--no-wrap' then @options[:width] = nil
        when '--all' then @options[:all] = true
        when '-v', '--verbose' then @options[:verbose] = true
        when '-q', '--quiet' then @options[:quiet] = true
        when '--json' then @options[:json] = true
        when '-h', '--help' then @options[:help] = true
        when '--no-emoji' then @options[:no_emoji] = true
        when '--no-reactions' then @options[:no_reactions] = true
        when '--no-names' then @options[:no_names] = true
        when '--reaction-names' then @options[:reaction_names] = true
        when '--reaction-timestamps' then @options[:reaction_timestamps] = true
        else handle_option(arg, args, remaining)
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

      def parse_width_option(args)
        value = args.shift
        @options[:width] = value == '0' ? nil : value.to_i
      end

      protected

      # Override in subclass to handle command-specific options
      # Return true if option was handled, false to raise unknown option error
      def handle_option(arg, _args, _remaining) # rubocop:disable Naming/PredicateMethod
        # By default, unknown options are errors
        # Subclasses can override and return true to accept the option,
        # or call super to get this error behavior
        @unknown_options ||= []
        @unknown_options << arg
        false
      end

      # Check for unknown options and return error code if any were passed
      def check_unknown_options
        return nil if @unknown_options.nil? || @unknown_options.empty?

        error("Unknown option: #{@unknown_options.first}")
        error('Run with --help for available options.')
        1
      end

      # Returns true if there are unknown options
      def unknown_options?
        @unknown_options&.any?
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

      # Call at start of execute to check for help flag and unknown options
      # Returns exit code if should return early, nil otherwise
      def validate_options
        return show_help if show_help?
        return check_unknown_options if unknown_options?

        nil
      end

      def help_text
        'No help available for this command.'
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
        1
      end

      def debug(message)
        output.debug(message) if @options[:verbose]
      end

      def puts(message = '')
        output.puts(message) unless @options[:quiet]
      end

      def print(message)
        output.print(message) unless @options[:quiet]
      end

      # JSON output helper
      def output_json(data)
        output.puts(JSON.pretty_generate(data))
      end

      # Build format options hash for message formatting
      # Subclasses can override to add command-specific options
      def format_options
        {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          no_names: @options[:no_names],
          reaction_names: @options[:reaction_names],
          reaction_timestamps: @options[:reaction_timestamps],
          width: @options[:width]
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
