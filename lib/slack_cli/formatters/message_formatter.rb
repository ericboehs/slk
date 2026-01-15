# frozen_string_literal: true

module SlackCli
  module Formatters
    # Formats Slack messages for terminal display or JSON output
    class MessageFormatter
      def initialize(output:, mention_replacer:, emoji_replacer:, cache_store:, api_client: nil, on_debug: nil)
        @output = output
        @mentions = mention_replacer
        @emoji = emoji_replacer
        @cache = cache_store
        @api_client = api_client
        @on_debug = on_debug
      end

      def format(message, workspace:, options: {})
        username = resolve_username(message, workspace, options)
        timestamp = format_timestamp(message.timestamp)
        text = process_text(message.text, workspace, options)

        # Build the header: [timestamp] username:
        header = "#{@output.blue("[#{timestamp}]")} #{@output.bold(username)}:"
        header_visible_width = visible_length("[#{timestamp}] #{username}: ")

        # Preserve newlines in message text (just strip leading/trailing whitespace)
        display_text = text.strip

        # Wrap text if width is specified
        width = options[:width]
        if width && width > header_visible_width && !display_text.empty?
          # First line has less space (width minus header), continuation lines use full width
          first_line_width = width - header_visible_width
          display_text = wrap_text(display_text, first_line_width, width)
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
        parts = message.reactions.map do |r|
          emoji = options[:no_emoji] ? r.emoji_code : (@emoji.lookup_emoji(r.name) || r.emoji_code)
          "#{r.count} #{emoji}"
        end
        " [#{parts.join(', ')}]"
      end

      def format_json(message, workspace: nil, options: {})
        reactions_json = message.reactions.map do |r|
          reaction_hash = { name: r.name, count: r.count }

          # Always return user objects with id, name (if available), and reacted_at (if available)
          reaction_hash[:users] = r.users.map do |user_id|
            user_hash = { id: user_id }

            # Try to resolve display name
            unless options[:no_names]
              workspace_name = workspace&.name
              if workspace_name
                cached_name = @cache.get_user(workspace_name, user_id)
                user_hash[:name] = cached_name if cached_name
              end
            end

            # Add timestamp if available
            if r.timestamps?
              timestamp = r.timestamp_for(user_id)
              if timestamp
                user_hash[:reacted_at] = timestamp
                user_hash[:reacted_at_iso8601] = Time.at(timestamp.to_f).iso8601
              end
            end

            user_hash
          end

          reaction_hash
        end

        result = {
          ts: message.ts,
          user_id: message.user_id,
          text: message.text,
          reactions: reactions_json,
          reply_count: message.reply_count,
          thread_ts: message.thread_ts,
          attachments: message.attachments,
          files: message.files
        }

        # Add resolved user name if available
        unless options[:no_names]
          workspace_name = workspace&.name
          if workspace_name
            user_name = @cache.get_user(workspace_name, message.user_id)
            result[:user_name] = user_name if user_name
          end
        end

        # Add channel info if available
        if options[:channel_id]
          result[:channel_id] = options[:channel_id]
          workspace_name = workspace&.name
          if workspace_name
            channel_name = @cache.get_channel_name(workspace_name, options[:channel_id])
            result[:channel_name] = channel_name if channel_name
          end
        end

        result
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

      # Calculate visible length of text (excluding ANSI escape codes)
      def visible_length(text)
        text.gsub(/\e\[[0-9;]*m/, '').length
      end

      # Wrap text to width, handling first line differently and preserving existing newlines
      def wrap_text(text, first_line_width, continuation_width)
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
            processed_text = wrap_text(processed_text, width - 2, width - 2) if width && width > 2

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
          processed = wrap_text(processed, width - 2, width - 2) if width && width > 2

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
          format_reactions_with_timestamps(message, lines, workspace, options)
        else
          # Standard reaction display
          reaction_text = message.reactions.map do |r|
            emoji = options[:no_emoji] ? r.emoji_code : (@emoji.lookup_emoji(r.name) || r.emoji_code)
            "#{r.count} #{emoji}"
          end.join('  ')

          lines << @output.yellow("[#{reaction_text}]")
        end
      end

      def format_reactions_with_timestamps(message, lines, workspace, options)
        workspace_name = workspace&.name

        message.reactions.each do |reaction|
          emoji = options[:no_emoji] ? reaction.emoji_code : (@emoji.lookup_emoji(reaction.name) || reaction.emoji_code)

          # Group users with their timestamps
          user_strings = reaction.users.map do |user_id|
            username = resolve_user_for_reaction(user_id, workspace_name, options)
            timestamp = reaction.timestamp_for(user_id)

            if timestamp
              time_str = format_reaction_time(timestamp)
              "#{username} (#{time_str})"
            else
              username
            end
          end

          lines << @output.yellow("  ↳ #{emoji} #{user_strings.join(', ')}")
        end
      end

      def resolve_user_for_reaction(user_id, workspace_name, options)
        return user_id if options[:no_names]

        # Try cache lookup
        if workspace_name
          cached = @cache.get_user(workspace_name, user_id)
          return cached if cached
        end

        # Fall back to user ID
        user_id
      end

      def format_reaction_time(slack_timestamp)
        time = Time.at(slack_timestamp.to_f)
        time.strftime('%-I:%M %p') # e.g., "2:45 PM"
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
