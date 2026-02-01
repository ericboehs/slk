# frozen_string_literal: true

module Slk
  module Formatters
    # Markdown output adapter with same interface as Output
    # Produces markdown formatting instead of ANSI colors
    class MarkdownOutput
      attr_reader :verbose, :quiet

      # Accept color: parameter for interface compatibility with Output (ignored for markdown)
      def initialize(io: $stdout, err: $stderr, color: nil, verbose: false, quiet: false) # rubocop:disable Lint/UnusedMethodArgument
        @io = io
        @err = err
        @verbose = verbose
        @quiet = quiet
      end

      def puts(message = '')
        @io.puts(message) unless @quiet
      end

      def print(message)
        @io.print(message) unless @quiet
      end

      def error(message)
        @err.puts("**Error:** #{message}")
      end

      def warn(message)
        @err.puts("*Warning:* #{message}") unless @quiet
      end

      def success(message)
        puts("✓ #{message}")
      end

      def info(message)
        puts(message)
      end

      def debug(message)
        return unless @verbose

        @err.puts("*[debug]* #{message}")
      end

      # Markdown formatting helpers - string interpolation handles nil conversion
      # bold -> **text**
      def bold(text)
        "**#{text}**"
      end

      # red -> **text** (emphasis for errors)
      def red(text)
        "**#{text}**"
      end

      # green -> plain text (success doesn't need markup)
      def green(text)
        text.to_s
      end

      # yellow -> *text* (italics for warnings)
      def yellow(text)
        "*#{text}*"
      end

      # blue -> `text` (code for timestamps)
      def blue(text)
        "`#{text}`"
      end

      # magenta -> *text* (italics for secondary)
      def magenta(text)
        "*#{text}*"
      end

      # cyan -> `text` (code for metadata like timestamps)
      def cyan(text)
        "`#{text}`"
      end

      # gray -> *text* (italics for secondary info)
      def gray(text)
        "*#{text}*"
      end

      def with_verbose(value)
        self.class.new(io: @io, err: @err, verbose: value, quiet: @quiet)
      end

      def with_quiet(value)
        self.class.new(io: @io, err: @err, verbose: @verbose, quiet: value)
      end
    end
  end
end
