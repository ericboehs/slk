# frozen_string_literal: true

module SlackCli
  module Models
    Status = Data.define(:text, :emoji, :expiration) do
      def initialize(text: "", emoji: "", expiration: 0)
        super(
          text: text.to_s.freeze,
          emoji: emoji.to_s.freeze,
          expiration: expiration.to_i
        )
      end

      def empty?
        text.empty? && emoji.empty?
      end

      def expires?
        expiration > 0
      end

      def expired?
        expires? && expiration < Time.now.to_i
      end

      def time_remaining
        return nil unless expires?

        remaining = expiration - Time.now.to_i
        remaining > 0 ? Duration.new(seconds: remaining) : nil
      end

      def expiration_time
        return nil unless expires?

        Time.at(expiration)
      end

      def to_s
        return "(no status)" if empty?

        parts = []
        parts << emoji unless emoji.empty?
        parts << text unless text.empty?

        if (remaining = time_remaining)
          parts << "(#{remaining})"
        end

        parts.join(" ")
      end
    end
  end
end
