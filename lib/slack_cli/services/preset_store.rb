# frozen_string_literal: true

module SlackCli
  module Services
    # Manages saved status presets in JSON format
    class PresetStore
      DEFAULT_PRESETS = {
        'meeting' => {
          'text' => 'In a meeting',
          'emoji' => ':calendar:',
          'duration' => '1h',
          'presence' => '',
          'dnd' => ''
        },
        'lunch' => {
          'text' => 'Lunch',
          'emoji' => ':knife_fork_plate:',
          'duration' => '1h',
          'presence' => 'away',
          'dnd' => ''
        },
        'focus' => {
          'text' => 'Focus time',
          'emoji' => ':headphones:',
          'duration' => '2h',
          'presence' => '',
          'dnd' => '2h'
        },
        'brb' => {
          'text' => 'Be right back',
          'emoji' => ':brb:',
          'duration' => '15m',
          'presence' => 'away',
          'dnd' => ''
        },
        'clear' => {
          'text' => '',
          'emoji' => '',
          'duration' => '0',
          'presence' => 'auto',
          'dnd' => 'off'
        }
      }.freeze

      attr_accessor :on_warning

      def initialize(paths: nil)
        @paths = paths || Support::XdgPaths.new
        @on_warning = nil
        ensure_default_presets
      end

      def get(name)
        data = load_presets[name]
        return nil unless data

        Models::Preset.from_hash(name, data)
      end

      def all
        load_presets.map { |name, data| Models::Preset.from_hash(name, data) }
      end

      def names
        load_presets.keys
      end

      def exists?(name)
        load_presets.key?(name)
      end

      def add(preset)
        presets = load_presets
        presets[preset.name] = preset.to_h
        save_presets(presets)
      end

      def remove(name) # rubocop:disable Naming/PredicateMethod
        presets = load_presets
        removed = presets.delete(name)
        save_presets(presets) if removed
        !removed.nil?
      end

      private

      def ensure_default_presets
        return if File.exist?(presets_file)

        @paths.ensure_config_dir
        save_presets(DEFAULT_PRESETS)
      end

      def load_presets
        return {} unless File.exist?(presets_file)

        JSON.parse(File.read(presets_file))
      rescue JSON::ParserError => e
        @on_warning&.call("Presets file #{presets_file} is corrupted (#{e.message}). Using defaults.")
        {}
      end

      def save_presets(presets)
        @paths.ensure_config_dir
        File.write(presets_file, JSON.pretty_generate(presets))
      end

      def presets_file
        @paths.config_file('presets.json')
      end
    end
  end
end
