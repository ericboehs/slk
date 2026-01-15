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
      def wrap(text, first_line_width, continuation_width)
        result = []
        text.each_line do |paragraph|
          process_paragraph(paragraph.chomp, result, first_line_width, continuation_width)
        end
        result.join("\n")
      end

      def process_paragraph(paragraph, result, first_line_width, continuation_width)
        if paragraph.empty?
          result << ''
        else
          current_first_width = result.empty? ? first_line_width : continuation_width
          result << wrap_paragraph(paragraph, current_first_width, continuation_width)
        end
      end

      # Wrap a single paragraph (no internal newlines)
      def wrap_paragraph(text, first_width, rest_width)
        state = { lines: [], current_line: '', current_width: first_width, rest_width: rest_width }
        text.split(/(\s+)/).each { |word| process_word(word, state) }
        state[:lines] << state[:current_line] unless state[:current_line].empty?
        state[:lines].join("\n")
      end

      def process_word(word, state)
        if state[:current_line].empty?
          state[:current_line] = word
        elsif visible_length(state[:current_line]) + visible_length(word) <= state[:current_width]
          state[:current_line] += word
        else
          start_new_line(word, state)
        end
      end

      def start_new_line(word, state)
        state[:lines] << state[:current_line]
        state[:current_line] = word.lstrip
        state[:current_width] = state[:rest_width]
      end
    end
  end
end
