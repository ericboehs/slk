# frozen_string_literal: true

module Slk
  module Formatters
    # Terminal output with ANSI color support
    class Output
      COLORS = {
        red: "\e[0;31m",
        green: "\e[0;32m",
        yellow: "\e[0;33m",
        blue: "\e[0;34m",
        magenta: "\e[0;35m",
        cyan: "\e[0;36m",
        gray: "\e[0;90m",
        bold: "\e[1m",
        reset: "\e[0m"
      }.freeze

      attr_reader :verbose, :quiet

      def color? = @color

      def initialize(io: $stdout, err: $stderr, color: nil, verbose: false, quiet: false)
        @io = io
        @err = err
        @color = color.nil? ? io.tty? : color
        @verbose = verbose
        @quiet = quiet
        @last_progress_width = nil
      end

      def puts(message = '')
        @io.puts(message) unless @quiet
      end

      def print(message)
        @io.print(message) unless @quiet
      end

      def error(message)
        @err.puts(colorize("#{red('Error:')} #{message}"))
      end

      def warn(message)
        @err.puts(colorize("#{yellow('Warning:')} #{message}")) unless @quiet
      end

      def success(message)
        puts(colorize("#{green('✓')} #{message}"))
      end

      def info(message)
        puts(colorize(message))
      end

      # Transient progress on stderr: it never pollutes piped stdout, and it
      # overwrites itself rather than scrolling. Silent under --quiet, and
      # when stderr is not a terminal, since a log file full of half-drawn
      # counters helps nobody.
      def progress(message)
        return unless progress?

        @last_progress_width = message.length
        write_progress("\r#{message}")
      end

      # Erases whatever progress() last drew. Keyed off the saved width rather
      # than re-checking tty state: if a line was drawn, it gets cleaned up.
      def clear_progress
        return unless @last_progress_width

        write_progress("\r#{' ' * @last_progress_width}\r")
        @last_progress_width = nil
      end

      # This is decoration. It is often called from an ensure block cleaning
      # up after a real failure, and a closed or broken stderr must not
      # replace that failure with one about drawing a counter.
      def write_progress(text)
        @err.print(text)
        @err.flush
      rescue SystemCallError, IOError
        nil
      end

      def progress? = tty_err? && !@quiet

      def tty_err?
        @err.tty?
      rescue SystemCallError, IOError
        false
      end

      def debug(message)
        return unless @verbose

        @err.puts(colorize("#{gray('[debug]')} #{message}"))
      end

      # Color helpers
      def red(text) = wrap(:red, text)
      def green(text) = wrap(:green, text)
      def yellow(text) = wrap(:yellow, text)
      def blue(text) = wrap(:blue, text)
      def magenta(text) = wrap(:magenta, text)
      def cyan(text) = wrap(:cyan, text)
      def gray(text) = wrap(:gray, text)
      def bold(text) = wrap(:bold, text)

      def with_verbose(value)
        self.class.new(io: @io, err: @err, color: @color, verbose: value, quiet: @quiet)
      end

      def with_quiet(value)
        self.class.new(io: @io, err: @err, color: @color, verbose: @verbose, quiet: value)
      end

      private

      def wrap(color, text)
        return text.to_s unless @color

        "#{COLORS[color]}#{text}#{COLORS[:reset]}"
      end

      def colorize(text)
        text
      end
    end
  end
end
