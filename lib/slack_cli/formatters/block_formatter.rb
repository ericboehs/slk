# frozen_string_literal: true

module SlackCli
  module Formatters
    # Formats Slack Block Kit blocks for terminal display
    class BlockFormatter
      def initialize(text_processor:)
        @text_processor = text_processor
      end

      def format(blocks, main_text, lines, options)
        return unless blocks&.any?
        return if options[:no_blocks]

        block_texts = extract_texts(blocks)
        block_texts = filter_duplicate_texts(block_texts, main_text)

        return if block_texts.empty?

        lines << ''
        block_texts.each { |text| format_block_text(text, lines, options) }
      end

      private

      def extract_texts(blocks)
        return [] unless blocks.is_a?(Array)

        blocks.filter_map do |block|
          block.dig('text', 'text') if block['type'] == 'section'
        end
      end

      def filter_duplicate_texts(block_texts, main_text)
        normalized_main = normalize(main_text)
        block_texts.reject { |bt| normalize(bt) == normalized_main }
      end

      def normalize(text)
        text.to_s.gsub(/\s+/, ' ').strip.downcase
      end

      def format_block_text(block_text, lines, options)
        processed = @text_processor.call(block_text)
        processed = wrap_text(processed, options[:width])

        processed.each_line { |line| lines << "> #{line.chomp}" }
      end

      def wrap_text(text, width)
        return text unless width && width > 2

        Support::TextWrapper.wrap(text, width - 2, width - 2)
      end
    end
  end
end
