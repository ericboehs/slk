# frozen_string_literal: true

module Slk
  module Formatters
    # Formats Slack messages for terminal display or JSON output
    # rubocop:disable Metrics/ClassLength
    class MessageFormatter
      # rubocop:disable Metrics/ParameterLists
      def initialize(output:, mention_replacer:, emoji_replacer:, cache_store:, api_client: nil, on_debug: nil)
        @output = output
        @mentions = mention_replacer
        @emoji = emoji_replacer
        @cache = cache_store
        @api_client = api_client
        @on_debug = on_debug
        @reaction_formatter = build_reaction_formatter(output, emoji_replacer, cache_store)
        @json_formatter = JsonMessageFormatter.new(cache_store: cache_store)
      end
      # rubocop:enable Metrics/ParameterLists

      def build_reaction_formatter(output, emoji_replacer, cache_store)
        ReactionFormatter.new(output: output, emoji_replacer: emoji_replacer, cache_store: cache_store)
      end

      def format(message, workspace:, options: {})
        username = resolve_username(message, workspace, options)
        timestamp = format_timestamp(message.timestamp)
        text = process_text(message.text, workspace, options)

        header = build_header(timestamp, username)
        display_text = build_display_text(text, message, header, options)
        main_line = "#{header} #{display_text}"

        build_output_lines(main_line, message, workspace, options, display_text)
      end

      def format_simple(message, workspace:, options: {})
        username = resolve_username(message, workspace, options)
        timestamp = format_timestamp(message.timestamp)
        text = process_text(message.text, workspace, options)

        reaction_text = ''
        unless options[:no_reactions] || message.reactions.empty?
          reaction_text = format_reaction_inline(message, options)
        end

        "#{@output.blue("[#{timestamp}]")} #{@output.bold(username)}: #{text}#{reaction_text}"
      end

      def format_reaction_inline(message, options)
        @reaction_formatter.format_inline(message.reactions, options)
      end

      def format_json(message, workspace: nil, options: {})
        @json_formatter.format(message, workspace: workspace, options: options)
      end

      private

      def build_header(timestamp, username)
        "#{@output.blue("[#{timestamp}]")} #{@output.bold(username)}:"
      end

      def build_display_text(text, message, header, options)
        display_text = text.strip
        header_width = Support::TextWrapper.visible_length("#{header.gsub(/\e\[[0-9;]*m/, '')} ")

        display_text = wrap_display_text(display_text, header_width, options[:width])
        display_text = add_file_placeholder(message, options) if display_text.empty?

        display_text
      end

      def wrap_display_text(text, header_width, width)
        return text if text.empty? || !width || width <= header_width

        first_line_width = width - header_width
        Support::TextWrapper.wrap(text, first_line_width, width)
      end

      def add_file_placeholder(message, options)
        return '' unless message.files? && !options[:no_files]

        first_file = message.files.first
        file_name = first_file['name'] || 'file'
        @output.blue("[File: #{file_name}]")
      end

      def build_output_lines(main_line, message, workspace, options, display_text)
        lines = [main_line]
        text_processor = ->(txt) { process_text(txt, workspace, options) }

        BlockFormatter.new(text_processor: text_processor)
                      .format(message.blocks, message.text, lines, options)
        AttachmentFormatter.new(output: @output, text_processor: text_processor)
                           .format(message.attachments, lines, options)
        format_files(message, lines, options, skip_first: display_text.include?('[File:'))
        format_reactions(message, lines, workspace, options)
        format_thread_indicator(message, lines, options)

        lines.join("\n")
      end

      def resolve_username(message, workspace, options = {})
        return message.user_id if options[:no_names]
        return message.embedded_username if message.embedded_username

        user_lookup_for(workspace).resolve_name_or_bot(message.user_id) || message.user_id
      end

      def user_lookup_for(workspace)
        Services::UserLookup.new(
          cache_store: @cache,
          workspace: workspace,
          api_client: @api_client,
          on_debug: @on_debug
        )
      end

      def format_timestamp(time)
        time.strftime('%Y-%m-%d %H:%M')
      end

      def process_text(text, workspace, options)
        result = decode_html_entities(text.dup)
        result = @mentions.replace(result, workspace)
        result = @emoji.replace(result, workspace) unless options[:no_emoji]
        result
      end

      def decode_html_entities(text)
        text.gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>')
      end

      def format_files(message, lines, options, skip_first: false)
        return if options[:no_files]

        files = files_to_display(message.files, skip_first)
        files.each { |file| lines << @output.blue("[File: #{file['name'] || 'file'}]") }
      end

      def files_to_display(files, skip_first)
        return [] if files.empty?

        skip_first ? (files[1..] || []) : files
      end

      def format_reactions(message, lines, workspace, options)
        return if message.reactions.empty? || options[:no_reactions]

        if options[:reaction_timestamps] && message.reactions.any?(&:timestamps?)
          lines.concat(@reaction_formatter.format_with_timestamps(message.reactions, workspace, options))
        else
          lines << @reaction_formatter.format_summary(message.reactions, options)
        end
      end

      def format_thread_indicator(message, lines, options)
        return unless message.thread? && !options[:in_thread] && !options[:no_threads]

        reply_text = message.reply_count == 1 ? '1 reply' : "#{message.reply_count} replies"
        lines << @output.cyan("[#{reply_text}]")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
