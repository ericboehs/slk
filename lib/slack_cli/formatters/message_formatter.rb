# frozen_string_literal: true

module SlackCli
  module Formatters
    # Formats Slack messages for terminal display or JSON output
    class MessageFormatter
      # rubocop:disable Metrics/ParameterLists
      def initialize(output:, mention_replacer:, emoji_replacer:, cache_store:, api_client: nil, on_debug: nil)
        @output = output
        @mentions = mention_replacer
        @emoji = emoji_replacer
        @cache = cache_store
        @api_client = api_client
        @on_debug = on_debug
        @reaction_formatter = ReactionFormatter.new(
          output: output,
          emoji_replacer: emoji_replacer,
          cache_store: cache_store
        )
        @json_formatter = JsonMessageFormatter.new(cache_store: cache_store)
      end
      # rubocop:enable Metrics/ParameterLists

      def format(message, workspace:, options: {})
        username = resolve_username(message, workspace, options)
        timestamp = format_timestamp(message.timestamp)
        text = process_text(message.text, workspace, options)

        # Build the header: [timestamp] username:
        header = "#{@output.blue("[#{timestamp}]")} #{@output.bold(username)}:"
        header_visible_width = Support::TextWrapper.visible_length("[#{timestamp}] #{username}: ")

        # Preserve newlines in message text (just strip leading/trailing whitespace)
        display_text = text.strip

        # Wrap text if width is specified
        width = options[:width]
        if width && width > header_visible_width && !display_text.empty?
          # First line has less space (width minus header), continuation lines use full width
          first_line_width = width - header_visible_width
          display_text = Support::TextWrapper.wrap(display_text, first_line_width, width)
        end

        # If no text but there are files, put first file inline with header
        if display_text.empty? && message.files? && !options[:no_files]
          first_file = message.files.first
          file_name = first_file['name'] || 'file'
          display_text = @output.blue("[File: #{file_name}]")
        end

        main_line = "#{header} #{display_text}"

        lines = [main_line]

        format_blocks(message, lines, workspace, options)
        format_attachments(message, lines, workspace, options)
        format_files(message, lines, options, skip_first: display_text.include?('[File:'))
        format_reactions(message, lines, workspace, options)
        format_thread_indicator(message, lines, options)

        lines.join("\n")
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

      def resolve_username(message, workspace, options = {})
        # Skip lookups if --no-names
        return message.user_id if options[:no_names]

        # Try embedded profile first
        return message.embedded_username if message.embedded_username

        # Try cache
        cached = @cache.get_user(workspace.name, message.user_id)
        return cached if cached

        # For bot IDs (start with B), try bots.info API
        if message.user_id.start_with?('B') && @api_client
          bot_name = lookup_bot_name(workspace, message.user_id)
          return bot_name if bot_name
        end

        # Fall back to ID
        message.user_id
      end

      def lookup_bot_name(workspace, bot_id)
        bots_api = Api::Bots.new(@api_client, workspace, on_debug: @on_debug)
        name = bots_api.get_name(bot_id)
        if name
          # Cache for future lookups (persist to disk)
          @cache.set_user(workspace.name, bot_id, name, persist: true)
        end
        name
      end

      def format_timestamp(time)
        time.strftime('%Y-%m-%d %H:%M')
      end

      def process_text(text, workspace, options)
        result = text.dup

        # Decode HTML entities (Slack encodes these)
        result = decode_html_entities(result)

        # Replace mentions
        result = @mentions.replace(result, workspace)

        # Replace emoji (unless disabled)
        result = @emoji.replace(result, workspace) unless options[:no_emoji]

        result
      end

      def decode_html_entities(text)
        text
          .gsub('&amp;', '&')
          .gsub('&lt;', '<')
          .gsub('&gt;', '>')
      end

      def format_header(timestamp, username, message, options)
        parts = []
        parts << @output.blue("[#{timestamp}]")
        parts << @output.bold(username)

        parts << @output.cyan('(reply)') if message.reply? && !options[:in_thread]

        parts.join(' ')
      end

      def indent(text, spaces: 4)
        prefix = ' ' * spaces
        text.lines.map { |line| "#{prefix}#{line.chomp}" }.join("\n")
      end

      def format_attachments(message, lines, workspace, options)
        return if message.attachments.empty?
        return if options[:no_attachments]

        message.attachments.each do |att|
          att_text = att['text'] || att['fallback']
          image_url = att['image_url'] || att['thumb_url']
          title = att['title']

          # Skip if no text and no image
          next unless att_text || image_url

          # Blank line before attachment
          lines << ''

          # Show author if available (for linked messages, bot messages, etc.)
          author = att['author_name'] || att['author_subname']
          lines << "> #{@output.bold(author)}:" if author

          # Show text content if present
          if att_text
            # Process attachment text through the same pipeline as message text
            processed_text = process_text(att_text, workspace, options)

            # Wrap attachment text if width is specified (account for "> " prefix)
            width = options[:width]
            processed_text = Support::TextWrapper.wrap(processed_text, width - 2, width - 2) if width && width > 2

            # Prefix each line with > to show it's quoted/attachment content
            processed_text.each_line do |line|
              lines << "> #{line.chomp}"
            end
          end

          # Show image info if present
          next unless image_url

          # Extract filename from URL or use title
          filename = title || extract_filename_from_url(image_url)
          lines << "> [Image: #{filename}]"
        end
      end

      def format_blocks(message, lines, workspace, options)
        return unless message.blocks?
        return if options[:no_blocks]

        # Extract text content from blocks (skip if it duplicates the main text)
        block_texts = extract_block_texts(message.blocks)
        return if block_texts.empty?

        # Don't show blocks if they just repeat the main message text
        main_text_normalized = message.text.gsub(/\s+/, ' ').strip.downcase
        block_texts.reject! do |bt|
          bt.gsub(/\s+/, ' ').strip.downcase == main_text_normalized
        end
        return if block_texts.empty?

        # Blank line before blocks
        lines << ''

        block_texts.each do |block_text|
          # Process text through mention/emoji pipeline
          processed = process_text(block_text, workspace, options)

          # Wrap if width specified (account for "> " prefix)
          width = options[:width]
          processed = Support::TextWrapper.wrap(processed, width - 2, width - 2) if width && width > 2

          # Prefix each line with >
          processed.each_line do |line|
            lines << "> #{line.chomp}"
          end
        end
      end

      def extract_block_texts(blocks)
        return [] unless blocks.is_a?(Array)

        blocks.filter_map do |block|
          next unless block['type'] == 'section'

          block.dig('text', 'text')
        end
      end

      # Extract filename from a URL path, returning 'image' if parsing fails
      def extract_filename_from_url(url)
        File.basename(URI.parse(url).path)
      rescue URI::InvalidURIError
        'image'
      end

      def format_files(message, lines, options, skip_first: false)
        return if message.files.empty?
        return if options[:no_files]

        files_to_show = skip_first ? message.files[1..] : message.files
        return if files_to_show.nil? || files_to_show.empty?

        files_to_show.each do |file|
          name = file['name'] || 'file'
          lines << @output.blue("[File: #{name}]")
        end
      end

      def format_reactions(message, lines, workspace, options)
        return if message.reactions.empty?
        return if options[:no_reactions]

        # Check if we should show timestamps and if any reactions have them
        if options[:reaction_timestamps] && message.reactions.any?(&:timestamps?)
          lines.concat(@reaction_formatter.format_with_timestamps(message.reactions, workspace, options))
        else
          lines << @reaction_formatter.format_summary(message.reactions, options)
        end
      end

      def format_thread_indicator(message, lines, options)
        return unless message.thread?
        return if options[:in_thread]
        return if options[:no_threads]

        reply_text = message.reply_count == 1 ? '1 reply' : "#{message.reply_count} replies"
        lines << @output.cyan("[#{reply_text}]")
      end
    end
  end
end
