# frozen_string_literal: true

module SlackCli
  module Services
    class Configuration
      attr_accessor :on_warning

      def initialize(paths: Support::XdgPaths.new)
        @paths = paths
        @on_warning = nil
        @data = nil # Lazy load to allow on_warning to be set first
      end

      def primary_workspace
        data['primary_workspace']
      end

      def primary_workspace=(name)
        data['primary_workspace'] = name
        save_config
      end

      def ssh_key
        data['ssh_key']
      end

      def ssh_key=(path)
        data['ssh_key'] = path
        save_config
      end

      def emoji_dir
        data['emoji_dir']
      end

      def [](key)
        data[key]
      end

      def []=(key, value)
        data[key] = value
        save_config
      end

      def to_h
        data.dup
      end

      private

      def data
        @data ||= load_config
      end

      def config_file
        @paths.config_file('config.json')
      end

      def load_config
        return {} unless File.exist?(config_file)

        JSON.parse(File.read(config_file))
      rescue JSON::ParserError => e
        @on_warning&.call("Config file #{config_file} is corrupted (#{e.message}). Using defaults.")
        {}
      end

      def save_config
        @paths.ensure_config_dir
        File.write(config_file, JSON.pretty_generate(data))
      end
    end
  end
end
