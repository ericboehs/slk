# frozen_string_literal: true

module Slk
  module Formatters
    # Formats saved/later items for terminal display
    class SavedItemFormatter
      def initialize(output:, mention_replacer:, text_processor:, on_debug: nil)
        @output = output
        @mentions = mention_replacer
        @text_processor = text_processor
        @on_debug = on_debug
      end

      # Display a single saved item
      # @param truncate [Boolean] if true, truncate to single line at width instead of wrapping
      def display_item(item, workspace, message: nil, width: nil, truncate: false)
        status_badge = format_status_badge(item)
        due_info = format_due_info(item)

        # First line: status badge and due info
        header_parts = [status_badge, due_info].compact.reject(&:empty?)
        @output.puts header_parts.join(' | ') unless header_parts.empty?

        # Message content
        display_message(message, workspace, width: width, truncate: truncate) if message
        @output.puts # blank line between items
      end

      private

      def format_status_badge(item)
        badge = case item.state
                when 'completed' then '[completed]'
                when 'in_progress' then '[in_progress]'
                when 'saved' then '[saved]'
                else "[#{item.state}]"
                end

        # Color based on overdue status
        if item.overdue?
          @output.red(badge)
        elsif item.state == 'completed'
          @output.green(badge)
        elsif item.state == 'in_progress'
          @output.yellow(badge)
        else
          @output.blue(badge)
        end
      end

      def format_due_info(item)
        return '' unless item.due_date?

        time_diff = item.time_until_due
        formatted = format_time_difference(time_diff)

        if item.overdue?
          "Due: #{@output.red(formatted)}"
        else
          "Due: #{formatted}"
        end
      end

      def format_time_difference(seconds)
        abs_seconds = seconds.abs
        ago = seconds.negative?

        formatted = if abs_seconds < 60
                      "#{abs_seconds}s"
                    elsif abs_seconds < 3600
                      "#{abs_seconds / 60}m"
                    elsif abs_seconds < 86_400
                      "#{abs_seconds / 3600}h"
                    else
                      "#{abs_seconds / 86_400}d"
                    end

        ago ? "#{formatted} ago" : "in #{formatted}"
      end

      def display_message(message, workspace, width: nil, truncate: false)
        username = resolve_message_author(message, workspace)
        text = prepare_message_text(message, workspace)
        header = "  #{@output.bold(username)}: "
        header_width = Support::TextWrapper.visible_length(header)

        if truncate
          display_truncated_message(header, text, width, header_width)
        else
          display_wrapped_message(header, text, width, header_width)
        end
      end

      def display_truncated_message(header, text, width, header_width)
        # Single line, truncated at width
        first_line = text.lines.first&.strip || text
        max_text_width = width ? [width - header_width, 10].max : 100
        @output.puts "#{header}#{truncate_text(first_line, max_text_width)}"
      end

      def display_wrapped_message(header, text, width, header_width)
        # Full message with wrapping
        wrapped = wrap_text(text, header_width, width)
        lines = wrapped.lines

        first_line = lines.first&.rstrip || wrapped
        @output.puts "#{header}#{first_line}"
        lines[1..].each { |line| @output.puts "  #{line.rstrip}" } if lines.length > 1
      end

      def resolve_message_author(message, workspace)
        if message['user']
          @mentions.lookup_user_name(workspace, message['user']) || message['user']
        elsif message['bot_id']
          'Bot'
        else
          'Unknown'
        end
      end

      def prepare_message_text(message, workspace)
        @text_processor.process(message['text'], workspace)
      end

      def wrap_text(text, indent_width, width)
        return text if text.empty? || !width

        # If header is wider than target, first line gets no wrap, subsequent lines wrap at width - 2
        first_line_width = [width - indent_width, 10].max
        continuation_width = [width - 2, 10].max
        Support::TextWrapper.wrap(text, first_line_width, continuation_width)
      end

      def truncate_text(text, max_length)
        text.length > max_length ? "#{text[0...max_length]}..." : text
      end
    end
  end
end
