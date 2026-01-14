# frozen_string_literal: true

module SlackCli
  module Support
    # Shared module for inline image display in iTerm2/WezTerm/Mintty terminals
    # Includes special handling for tmux passthrough sequences
    module InlineImages
      # Check if terminal supports iTerm2 inline image protocol
      def inline_images_supported?
        # iTerm2, WezTerm, Mintty support inline images
        # LC_TERMINAL persists through tmux/ssh
        ENV["TERM_PROGRAM"] == "iTerm.app" ||
          ENV["TERM_PROGRAM"] == "WezTerm" ||
          ENV["LC_TERMINAL"] == "iTerm2" ||
          ENV["LC_TERMINAL"] == "WezTerm" ||
          ENV["TERM"] == "mintty"
      end

      # Check if running inside tmux
      def in_tmux?
        # tmux sets TERM to screen-* or tmux-*
        ENV["TERM"]&.include?("screen") || ENV["TERM"]&.start_with?("tmux")
      end

      # Print an inline image using iTerm2 protocol
      # In tmux, uses passthrough sequence and cursor positioning
      def print_inline_image(path, height: 1)
        return unless File.exist?(path)

        begin
          data = File.binread(path)
        rescue IOError, SystemCallError
          # File exists but can't be read - skip silently
          return
        end
        encoded = [data].pack("m0") # Base64 encode

        if in_tmux?
          # tmux passthrough: \n + space required for image to render
          printf "\ePtmux;\e\e]1337;File=inline=1;preserveAspectRatio=0;size=%d;height=%d:%s\a\e\\\n ",
                 encoded.length, height, encoded
        else
          # Standard iTerm2 format
          printf "\e]1337;File=inline=1;height=%d:%s\a", height, encoded
        end
      end

      # Print inline image with name on same line
      # Handles tmux cursor positioning to keep image and text on same line
      def print_inline_image_with_text(path, text, height: 1)
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
