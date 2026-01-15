# frozen_string_literal: true

module Slk
  module Models
    Status = Data.define(:text, :emoji, :expiration) do
      def initialize(text: '', emoji: '', expiration: 0)
        exp_val = expiration.to_i
        exp_val = 0 if exp_val.negative? # Normalize invalid negative expirations

        super(
          text: text.to_s.freeze,
          emoji: emoji.to_s.freeze,
          expiration: exp_val
        )
      end

      def empty?
        text.empty? && emoji.empty?
      end

      def expires?
        expiration.positive?
      end

      def expired?
        expires? && expiration < Time.now.to_i
      end

      def time_remaining
        return nil unless expires?

        remaining = expiration - Time.now.to_i
        remaining.positive? ? Duration.new(seconds: remaining) : nil
      end

      def expiration_time
        return nil unless expires?

        Time.at(expiration)
      end

      def to_s
        return '(no status)' if empty?

        parts = []
        parts << emoji unless emoji.empty?
        parts << text unless text.empty?

        if (remaining = time_remaining)
          parts << "(#{remaining})"
        end

        parts.join(' ')
      end
    end
  end
end
