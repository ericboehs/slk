# frozen_string_literal: true

require 'open3'

module Slk
  module Support
    # Renders downloaded image attachments inline using chafa, which handles
    # Kitty graphics (Ghostty/Kitty) and iTerm2 images, including tmux
    # passthrough with Unicode placeholders so images scroll with the pane.
    # Without a capable terminal or chafa, callers just show the file path.
    # Set SLK_IMAGE_PREVIEW=0 (or false/no/off) to turn previews off.
    # Expects Support::InlineImages to be included alongside.
    module ImagePreview
      PREVIEW_MAX_COLS = 100
      PREVIEW_MAX_ROWS = 15
      PREVIEWABLE_EXTENSIONS = %w[png jpg jpeg gif webp bmp tif tiff heic].freeze
      DISABLED_VALUES = %w[0 false no off].freeze

      private

      def image_previews_supported?
        return @image_previews_supported if defined?(@image_previews_supported)

        @image_previews_supported = !image_previews_disabled_by_env? && $stdout.tty? &&
                                    !image_preview_format.nil? && chafa_available?
      end

      def image_previews_disabled_by_env?
        DISABLED_VALUES.include?(ENV.fetch('SLK_IMAGE_PREVIEW', '').strip.downcase)
      end

      def image_preview_format
        if kitty_graphics_supported?
          'kitty'
        elsif iterm2_protocol_supported?
          'iterm'
        end
      end

      def previewable_image?(path)
        PREVIEWABLE_EXTENSIONS.include?(File.extname(path.to_s).delete('.').downcase)
      end

      # Print an inline preview of the image at path, indented by indent columns.
      # @return [Boolean] whether a preview was printed
      def print_image_preview(path, indent: 2) # rubocop:disable Naming/PredicateMethod
        return false unless previewable_image?(path) && File.exist?(path)

        rendered = render_image_preview(path, indent)
        return false unless rendered

        $stdout.print(' ' * indent)
        $stdout.print(rendered)
        $stdout.print("\n") unless rendered.end_with?("\n", "\e[?25h")
        $stdout.flush
        true
      end

      def render_image_preview(path, indent)
        stdout, _stderr, status = Open3.capture3(*chafa_args(path, indent))
        status.success? && !stdout.empty? ? stdout : nil
      rescue SystemCallError => e
        debug("chafa failed: #{e.message}") if respond_to?(:debug, true)
        nil
      end

      def chafa_args(path, indent)
        args = ['chafa', "--format=#{image_preview_format}"]
        args << '--passthrough=tmux' if in_tmux?
        args + ["--size=#{preview_cols(indent)}x#{PREVIEW_MAX_ROWS}",
                '--animate=off', '--probe=off', '--relative=off', path]
      end

      def preview_cols(indent)
        [terminal_columns - indent - 1, PREVIEW_MAX_COLS].min.clamp(10, PREVIEW_MAX_COLS)
      end

      def terminal_columns
        require 'io/console'
        cols = IO.console&.winsize&.last.to_i
        cols.positive? ? cols : 80
      rescue StandardError
        80
      end

      def chafa_available?
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
          File.executable?(File.join(dir, 'chafa'))
        end
      end
    end
  end
end
