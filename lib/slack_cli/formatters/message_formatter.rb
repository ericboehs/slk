# frozen_string_literal: true

module SlackCli
  module Formatters
    class MessageFormatter
      def initialize(output:, mention_replacer:, emoji_replacer:, cache_store:, api_client: nil)
        @output = output
        @mentions = mention_replacer
        @emoji = emoji_replacer
        @cache = cache_store
        @api_client = api_client
      end

      def format(message, workspace:, options: {})
        username = resolve_username(message, workspace, options)
        timestamp = format_timestamp(message.timestamp)
        text = process_text(message.text, workspace, options)

        lines = []
        lines << "#{format_header(timestamp, username, message, options)}:"

        lines << text unless text.empty?

        format_attachments(message, lines, options)
        format_files(message, lines, options)
        format_reactions(message, lines, options)
        format_thread_indicator(message, lines, options)

        lines.join("\n")
      end

      def format_simple(message, workspace:, options: {})
        username = resolve_username(message, workspace, options)
        timestamp = format_timestamp(message.timestamp)
        text = process_text(message.text, workspace, options)

        reaction_text = ""
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
        " [#{parts.join(", ")}]"
      end

      def format_json(message)
        {
          ts: message.ts,
          user: message.user_id,
          text: message.text,
          reactions: message.reactions.map { |r| { name: r.name, count: r.count } },
          reply_count: message.reply_count,
          thread_ts: message.thread_ts
        }
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
        if message.user_id.start_with?("B") && @api_client
          bot_name = lookup_bot_name(workspace, message.user_id)
          return bot_name if bot_name
        end

        # Fall back to ID
        message.user_id
      end

      def lookup_bot_name(workspace, bot_id)
        bots_api = Api::Bots.new(@api_client, workspace)
        name = bots_api.get_name(bot_id)
        if name
          # Cache for future lookups (persist to disk)
          @cache.set_user(workspace.name, bot_id, name, persist: true)
        end
        name
      end

      def format_timestamp(time)
        time.strftime("%Y-%m-%d %H:%M")
      end

      def process_text(text, workspace, options)
        result = text.dup

        # Replace mentions
        result = @mentions.replace(result, workspace)

        # Replace emoji (unless disabled)
        unless options[:no_emoji]
          result = @emoji.replace(result, workspace)
        end

        result
      end

      def format_header(timestamp, username, message, options)
        parts = []
        parts << @output.blue("[#{timestamp}]")
        parts << @output.bold(username)

        if message.is_reply? && !options[:in_thread]
          parts << @output.cyan("(reply)")
        end

        parts.join(" ")
      end

      def indent(text, spaces: 4)
        prefix = " " * spaces
        text.lines.map { |line| "#{prefix}#{line.chomp}" }.join("\n")
      end

      def format_attachments(message, lines, options)
        return if message.attachments.empty?
        return if options[:no_attachments]

        message.attachments.each do |att|
          if att["text"]
            lines << @output.gray("| #{att["text"]}")
          elsif att["fallback"]
            lines << @output.gray("| #{att["fallback"]}")
          end
        end
      end

      def format_files(message, lines, options)
        return if message.files.empty?
        return if options[:no_files]

        message.files.each do |file|
          name = file["name"] || "file"
          url = file["url_private"] || file["permalink"]
          lines << @output.blue("[File: #{name}]")
          lines << @output.gray(url) if url && !options[:no_urls]
        end
      end

      def format_reactions(message, lines, options)
        return if message.reactions.empty?
        return if options[:no_reactions]

        reaction_text = message.reactions.map do |r|
          emoji = options[:no_emoji] ? r.emoji_code : (@emoji.lookup_emoji(r.name) || r.emoji_code)
          "#{r.count} #{emoji}"
        end.join("  ")

        lines << @output.yellow("[#{reaction_text}]")
      end

      def format_thread_indicator(message, lines, options)
        return unless message.has_thread?
        return if options[:in_thread]
        return if options[:no_threads]

        reply_text = message.reply_count == 1 ? "1 reply" : "#{message.reply_count} replies"
        lines << @output.cyan("[#{reply_text}]")
      end
    end
  end
end
