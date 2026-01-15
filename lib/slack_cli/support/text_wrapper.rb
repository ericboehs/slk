# frozen_string_literal: true

module SlackCli
  module Support
    # Text wrapping utilities with ANSI escape code awareness
    module TextWrapper
      module_function

      # Calculate visible length of text (excluding ANSI escape codes)
      def visible_length(text)
        text.gsub(/\e\[[0-9;]*m/, '').length
      end

      # Wrap text to width, handling first line differently and preserving existing newlines
      # @param text [String] Text to wrap
      # @param first_line_width [Integer] Width for first line
      # @param continuation_width [Integer] Width for subsequent lines
      # @return [String] Wrapped text
      def wrap(text, first_line_width, continuation_width)
        result = []

        text.each_line do |paragraph|
          paragraph = paragraph.chomp
          if paragraph.empty?
            result << ''
            next
          end

          # For each paragraph, wrap to width
          # First paragraph's first line uses first_line_width, all other lines use continuation_width
          current_first_width = result.empty? ? first_line_width : continuation_width
          wrapped = wrap_paragraph(paragraph, current_first_width, continuation_width)
          result << wrapped
        end

        result.join("\n")
      end

      # Wrap a single paragraph (no internal newlines)
      # @param text [String] Paragraph text
      # @param first_width [Integer] Width for first line
      # @param rest_width [Integer] Width for subsequent lines
      # @return [String] Wrapped paragraph
      def wrap_paragraph(text, first_width, rest_width)
        words = text.split(/(\s+)/)
        lines = []
        current_line = ''
        current_width = first_width

        words.each do |word|
          word_len = visible_length(word)

          if current_line.empty?
            current_line = word
          elsif visible_length(current_line) + word_len <= current_width
            current_line += word
          else
            lines << current_line
            current_line = word.lstrip
            current_width = rest_width
          end
        end

        lines << current_line unless current_line.empty?

        lines.join("\n")
      end
    end
  end
end
