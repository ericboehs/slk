# frozen_string_literal: true

module Slk
  module Support
    # Cross-platform utilities for OS-specific operations
    module Platform
      module_function

      def windows?
        Gem.win_platform?
      end

      def macos?
        RUBY_PLATFORM.include?('darwin')
      end

      def linux?
        RUBY_PLATFORM.include?('linux')
      end

      # Open a URL or file with the system's default handler.
      # Uses: open (macOS), start (Windows), xdg-open (Linux)
      def open_url(url)
        if windows?
          system('start', '', url)
        elsif macos?
          system('open', url)
        else
          system('xdg-open', url)
        end
      end
    end
  end
end
