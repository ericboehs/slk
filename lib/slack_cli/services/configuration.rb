# frozen_string_literal: true

module SlackCli
  module Services
    class Configuration
      def initialize(paths: Support::XdgPaths.new)
        @paths = paths
        @data = load_config
      end

      def primary_workspace
        @data["primary_workspace"]
      end

      def primary_workspace=(name)
        @data["primary_workspace"] = name
        save_config
      end

      def ssh_key
        @data["ssh_key"]
      end

      def ssh_key=(path)
        @data["ssh_key"] = path
        save_config
      end

      def emoji_dir
        @data["emoji_dir"]
      end

      def [](key)
        @data[key]
      end

      def []=(key, value)
        @data[key] = value
        save_config
      end

      def to_h
        @data.dup
      end

      private

      def config_file
        @paths.config_file("config.json")
      end

      def load_config
        return {} unless File.exist?(config_file)

        JSON.parse(File.read(config_file))
      rescue JSON::ParserError
        {}
      end

      def save_config
        @paths.ensure_config_dir
        File.write(config_file, JSON.pretty_generate(@data))
      end
    end
  end
end
