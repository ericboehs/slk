# frozen_string_literal: true

module Slk
  module Support
    # Cross-platform paths for config and cache directories.
    # Uses XDG Base Directory spec on Unix, APPDATA/LOCALAPPDATA on Windows.
    class XdgPaths
      WINDOWS = Gem.win_platform?

      def config_dir
        @config_dir ||= File.join(default_config_base, 'slk')
      end

      def cache_dir
        @cache_dir ||= File.join(default_cache_base, 'slk')
      end

      private

      def default_config_base
        return ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config')) unless WINDOWS

        ENV.fetch('APPDATA', File.join(Dir.home, 'AppData', 'Roaming'))
      end

      def default_cache_base
        return ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache')) unless WINDOWS

        ENV.fetch('LOCALAPPDATA', File.join(Dir.home, 'AppData', 'Local'))
      end

      public

      def config_file(filename)
        File.join(config_dir, filename)
      end

      def cache_file(filename)
        File.join(cache_dir, filename)
      end

      def ensure_config_dir
        FileUtils.mkdir_p(config_dir)
      end

      def ensure_cache_dir
        FileUtils.mkdir_p(cache_dir)
      end
    end
  end
end
