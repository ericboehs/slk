# frozen_string_literal: true

module SlackCli
  module Models
    Preset = Data.define(:name, :text, :emoji, :duration, :presence, :dnd) do
      def self.from_hash(name, data)
        new(
          name: name,
          text: data['text'] || '',
          emoji: data['emoji'] || '',
          duration: data['duration'] || '0',
          presence: data['presence'] || '',
          dnd: data['dnd'] || ''
        )
      end

      # rubocop:disable Metrics/ParameterLists
      def initialize(name:, text: '', emoji: '', duration: '0', presence: '', dnd: '')
        validate_name!(name)
        validate_duration!(duration)

        super(
          name: name.to_s.strip.freeze,
          text: text.to_s.freeze, emoji: emoji.to_s.freeze, duration: duration.to_s.freeze,
          presence: presence.to_s.freeze, dnd: dnd.to_s.freeze
        )
      end
      # rubocop:enable Metrics/ParameterLists

      def to_h
        { 'text' => text, 'emoji' => emoji, 'duration' => duration, 'presence' => presence, 'dnd' => dnd }
      end

      def duration_value
        Duration.parse(duration)
      end

      def sets_presence?
        !presence.empty?
      end

      def sets_dnd?
        !dnd.empty?
      end

      def clears_status?
        text.empty? && emoji.empty?
      end

      def to_s
        "#{name}: #{build_parts.join(' ')}"
      end

      private

      def validate_name!(name)
        raise ArgumentError, 'preset name cannot be empty' if name.to_s.strip.empty?
      end

      def validate_duration!(duration)
        duration_str = duration.to_s
        Duration.parse(duration_str) unless duration_str.empty? || duration_str == '0'
      end

      # rubocop:disable Metrics/AbcSize
      def build_parts
        parts = []
        parts << emoji unless emoji.empty?
        parts << "\"#{text}\"" unless text.empty?
        parts << "(#{duration})" unless duration == '0' || duration.empty?
        parts << "[#{presence}]" if sets_presence?
        parts << "{dnd: #{dnd}}" if sets_dnd?
        parts
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
