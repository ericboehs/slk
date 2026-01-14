# frozen_string_literal: true

module SlackCli
  module Support
    class XdgPaths
      def config_dir
        @config_dir ||= File.join(
          ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config')),
          'slk'
        )
      end

      def cache_dir
        @cache_dir ||= File.join(
          ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache')),
          'slk'
        )
      end

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
