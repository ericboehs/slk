# frozen_string_literal: true

module Slk
  module Support
    # Shared module for inline image display in iTerm2/WezTerm/Mintty terminals
    # Includes special handling for tmux passthrough sequences
    module InlineImages
      # Check if terminal supports iTerm2 inline image protocol
      def inline_images_supported?
        # iTerm2, WezTerm, Mintty support inline images
        # LC_TERMINAL persists through tmux/ssh
        ['iTerm.app', 'WezTerm'].include?(ENV.fetch('TERM_PROGRAM', nil)) ||
          ENV['LC_TERMINAL'] == 'iTerm2' ||
          ENV['LC_TERMINAL'] == 'WezTerm' ||
          ENV['TERM'] == 'mintty'
      end

      # Check if running inside tmux
      def in_tmux?
        # tmux sets TERM to screen-* or tmux-*
        ENV['TERM']&.include?('screen') || ENV['TERM']&.start_with?('tmux')
      end

      # Print an inline image using iTerm2 protocol
      # In tmux, uses passthrough sequence and cursor positioning
      def print_inline_image(path, height: 1)
        data = read_image_data(path)
        return unless data

        encoded = [data].pack('m0')
        in_tmux? ? print_tmux_image(encoded, height) : print_iterm_image(encoded, height)
      end

      def read_image_data(path)
        return nil unless File.exist?(path)

        File.binread(path)
      rescue IOError, SystemCallError
        nil
      end

      def print_tmux_image(encoded, height)
        fmt = "\ePtmux;\e\e]1337;File=inline=1;preserveAspectRatio=0;" \
              "size=%<size>d;height=%<height>d:%<data>s\a\e\\\n "
        printf fmt, size: encoded.length, height: height, data: encoded
      end

      def print_iterm_image(encoded, height)
        printf "\e]1337;File=inline=1;height=%<height>d:%<data>s\a", height: height, data: encoded
      end

      # Print inline image with name on same line
      # Handles tmux cursor positioning to keep image and text on same line
      def print_inline_image_with_text(path, text, height: 1) # rubocop:disable Naming/PredicateMethod
        return false unless inline_images_supported? && File.exist?(path)

        print_inline_image(path, height: height)

        if in_tmux?
          # tmux: image ends with \n + space, cursor on next line
          # Move up 1 line, right 3 cols (past image), then print text
          print "\e[1A\e[3C#{text}\n"
        else
          puts " #{text}"
        end

        true
      end
    end
  end
end
