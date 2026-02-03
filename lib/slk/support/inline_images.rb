# frozen_string_literal: true

module Slk
  module Support
    # Shared module for inline image display in terminals supporting
    # iTerm2 protocol (iTerm2/WezTerm/Mintty) or Kitty graphics protocol (Ghostty/Kitty)
    # Includes special handling for tmux passthrough sequences
    module InlineImages
      # Check if terminal supports any inline image protocol
      def inline_images_supported?
        iterm2_protocol_supported? || kitty_graphics_supported?
      end

      # Check if terminal supports iTerm2 inline image protocol
      def iterm2_protocol_supported?
        # iTerm2, WezTerm, Mintty support inline images
        # LC_TERMINAL persists through tmux/ssh
        ['iTerm.app', 'WezTerm'].include?(ENV.fetch('TERM_PROGRAM', nil)) ||
          ENV['LC_TERMINAL'] == 'iTerm2' ||
          ENV['LC_TERMINAL'] == 'WezTerm' ||
          ENV['TERM'] == 'mintty'
      end

      # Check if terminal supports Kitty graphics protocol (Ghostty, Kitty)
      def kitty_graphics_supported?
        ENV['TERM_PROGRAM'] == 'ghostty' ||
          ENV['GHOSTTY_RESOURCES_DIR'] ||
          ENV['TERM']&.include?('kitty') ||
          tmux_client_is_kitty_compatible?
      end

      # Check if tmux client terminal supports Kitty graphics
      def tmux_client_is_kitty_compatible?
        return false unless in_tmux?

        @tmux_client_is_kitty_compatible ||= begin
          output = begin
            `tmux display-message -p '\#{client_termname}'`.chomp
          rescue StandardError
            ''
          end
          output.include?('ghostty') || output.include?('kitty')
        end
      end

      # Check if running inside tmux
      def in_tmux?
        # tmux sets TERM to screen-* or tmux-*
        ENV['TERM']&.include?('screen') || ENV['TERM']&.start_with?('tmux')
      end

      # Print an inline image using the appropriate protocol
      # In tmux, uses passthrough sequence and cursor positioning
      def print_inline_image(path, height: 1)
        data = read_image_data_for_protocol(path)
        return unless data

        encoded = [data].pack('m0')

        if kitty_graphics_supported?
          in_tmux? ? print_tmux_kitty_image(encoded, height) : print_kitty_image(encoded, height)
        else
          in_tmux? ? print_tmux_iterm_image(encoded, height) : print_iterm_image(encoded, height)
        end
      end

      def read_image_data_for_protocol(path)
        return nil unless File.exist?(path)

        data = File.binread(path)
        return nil unless data

        # Kitty protocol requires PNG format; convert GIF/JPEG if needed
        if kitty_graphics_supported? && !png_data?(data)
          convert_to_png(path)
        else
          data
        end
      rescue IOError, SystemCallError
        nil
      end

      def png_data?(data)
        # PNG files start with magic bytes: 137 80 78 71 13 10 26 10
        data[0, 8]&.bytes == [137, 80, 78, 71, 13, 10, 26, 10]
      end

      def convert_to_png(path)
        # Use sips (macOS) to convert to PNG
        require 'tempfile'
        temp = Tempfile.new(['emoji', '.png'])
        temp.close

        system('sips', '-s', 'format', 'png', path, '--out', temp.path,
               out: File::NULL, err: File::NULL)

        return nil unless File.exist?(temp.path) && File.size(temp.path).positive?

        File.binread(temp.path)
      ensure
        temp&.unlink
      end

      # iTerm2 protocol methods
      def print_tmux_iterm_image(encoded, height)
        fmt = "\ePtmux;\e\e]1337;File=inline=1;preserveAspectRatio=0;" \
              "size=%<size>d;height=%<height>d:%<data>s\a\e\\\n "
        printf fmt, size: encoded.length, height: height, data: encoded
      end

      def print_iterm_image(encoded, height)
        printf "\e]1337;File=inline=1;height=%<height>d:%<data>s\a", height: height, data: encoded
      end

      # Kitty graphics protocol methods (Ghostty, Kitty)
      # Format: \e_Ga=T,q=1,f=100,r=<rows>,m=0;<base64-data>\e\\
      # a=T: transmit and display, q=1: suppress OK response, f=100: PNG, r=rows, m=0: no more chunks
      def print_kitty_image(encoded, height)
        printf "\e_Ga=T,q=1,f=100,r=%d,m=0;%s\e\\", height, encoded
      end

      # Kitty graphics with Unicode placeholders for tmux
      # Uses U+10EEEE placeholder character so images clear/scroll with text
      # See: https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders
      def print_tmux_kitty_image(encoded, _height)
        @kitty_image_id ||= 30
        @kitty_image_id = (@kitty_image_id % 255) + 1
        image_id = @kitty_image_id

        # Single row with 2 columns for inline display
        cols = 2
        rows = 1

        # tmux passthrough for graphics command (inner escapes doubled)
        # Transmit image with Unicode placeholder mode (U=1), q=1 suppresses OK response
        $stdout.print "\ePtmux;\e\e_Ga=T,U=1,q=1,f=100,i=#{image_id},c=#{cols},r=#{rows},m=0;#{encoded}\e\e\\\e\\"

        # Output placeholder cells with foreground color set to image_id
        # Each cell needs U+10EEEE + row_diacritic + col_diacritic
        # Diacritics: U+0305=0, U+030D=1
        # Output 2 cells side by side for col 0 and col 1
        $stdout.print "\e[38;5;#{image_id}m"
        $stdout.print "\u{10EEEE}\u0305\u0305"  # row 0, col 0
        $stdout.print "\u{10EEEE}\u0305\u030D"  # row 0, col 1
        $stdout.print "\e[39m"
        $stdout.flush
      end

      # Print inline image with name on same line
      # Handles tmux cursor positioning to keep image and text on same line
      def print_inline_image_with_text(path, text, height: 1) # rubocop:disable Naming/PredicateMethod
        return false unless inline_images_supported? && File.exist?(path)

        print_inline_image(path, height: height)

        if in_tmux? && kitty_graphics_supported?
          # Unicode placeholders are regular text, just print after them
          puts " #{text}"
        elsif in_tmux?
          # iTerm2 in tmux: image ends with \n + space, cursor on next line
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
