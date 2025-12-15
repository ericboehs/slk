# frozen_string_literal: true

module SlackCli
  module Models
    Preset = Data.define(:name, :text, :emoji, :duration, :presence, :dnd) do
      def self.from_hash(name, data)
        new(
          name: name,
          text: data["text"] || "",
          emoji: data["emoji"] || "",
          duration: data["duration"] || "0",
          presence: data["presence"] || "",
          dnd: data["dnd"] || ""
        )
      end

      def initialize(name:, text: "", emoji: "", duration: "0", presence: "", dnd: "")
        super(
          name: name.to_s.freeze,
          text: text.to_s.freeze,
          emoji: emoji.to_s.freeze,
          duration: duration.to_s.freeze,
          presence: presence.to_s.freeze,
          dnd: dnd.to_s.freeze
        )
      end

      def to_h
        {
          "text" => text,
          "emoji" => emoji,
          "duration" => duration,
          "presence" => presence,
          "dnd" => dnd
        }
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
        parts = []
        parts << emoji unless emoji.empty?
        parts << "\"#{text}\"" unless text.empty?
        parts << "(#{duration})" unless duration == "0" || duration.empty?
        parts << "[#{presence}]" if sets_presence?
        parts << "{dnd: #{dnd}}" if sets_dnd?

        "#{name}: #{parts.join(" ")}"
      end
    end
  end
end
