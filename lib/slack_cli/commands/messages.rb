# frozen_string_literal: true

require_relative '../support/help_formatter'
require_relative '../support/inline_images'

module SlackCli
  module Commands
    # Reads messages from channels, DMs, or threads
    class Messages < Base
      include Support::InlineImages

      def execute
        result = validate_options
        return result if result

        target = positional_args.first
        unless target
          error('Usage: slk messages <channel|@user|url>')
          return 1
        end

        resolved = target_resolver.resolve(target, default_workspace: target_workspaces.first)
        workspace, channel_id, thread_ts, msg_ts = resolved.to_a

        apply_default_limit(msg_ts)
        messages = fetch_messages(workspace, channel_id, thread_ts, oldest: msg_ts)
        messages = enrich_reactions(messages, workspace, channel_id) if @options[:reaction_timestamps]

        if @options[:json]
          output_json_messages(messages, workspace, channel_id)
        else
          display_messages(messages, workspace, channel_id)
        end

        0
      rescue ApiError => e
        error("Failed to fetch messages: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(
          limit: 500,
          limit_set: false,
          threads: false,
          workspace_emoji: false
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-n', '--limit'
          @options[:limit] = args.shift.to_i
          @options[:limit_set] = true
        when '--threads'
          @options[:threads] = true
        when '--workspace-emoji'
          @options[:workspace_emoji] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk messages <target> [options]')
        help.description('Read messages from a channel, DM, or thread.')

        help.section('TARGET') do |s|
          s.item('#channel', 'Channel by name')
          s.item('channel', 'Channel by name (without #)')
          s.item('@user', 'Direct message with user')
          s.item('C123ABC', 'Channel by ID')
          s.item('<slack_url>', 'Slack message URL (returns message + subsequent)')
        end

        help.section('OPTIONS') do |s|
          s.option('-n, --limit N', 'Number of messages (default: 500, or 50 for message URLs)')
          s.option('--threads', 'Show thread replies inline')
          s.option('--no-emoji', 'Show :emoji: codes instead of unicode')
          s.option('--no-reactions', 'Hide reactions')
          s.option('--no-names', 'Skip user name lookups (faster)')
          s.option('--workspace-emoji', 'Show workspace emoji as inline images (experimental)')
          s.option('--reaction-names', 'Show reactions with user names')
          s.option('--reaction-timestamps', 'Show when each person reacted')
          s.option('--width N', 'Wrap text at N columns (default: 72 on TTY, no wrap otherwise)')
          s.option('--no-wrap', 'Disable text wrapping')
          s.option('--json', 'Output as JSON')
          s.option('-w, --workspace', 'Specify workspace')
          s.option('-v, --verbose', 'Show debug information')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def target_resolver
        @target_resolver ||= Services::TargetResolver.new(runner: runner, cache_store: cache_store)
      end

      def enrich_reactions(messages, workspace, channel_id)
        enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
        enricher.enrich_messages(messages, channel_id)
      end

      def output_json_messages(messages, workspace, channel_id)
        format_options = {
          no_names: @options[:no_names],
          reaction_timestamps: @options[:reaction_timestamps],
          channel_id: channel_id
        }
        output_json(messages.map do |m|
          runner.message_formatter.format_json(m, workspace: workspace, options: format_options)
        end)
      end

      # Apply default limit based on target type (50 for message URLs, 500 otherwise)
      def apply_default_limit(msg_ts)
        return if @options[:limit_set]

        @options[:limit] = msg_ts ? 50 : 500
      end

      def fetch_messages(workspace, channel_id, thread_ts = nil, oldest: nil)
        api = runner.conversations_api(workspace.name)

        if thread_ts
          # For threads, paginate to fetch all replies
          messages = fetch_all_thread_replies(api, channel_id, thread_ts)

          # Apply limit (keep parent + last N-1 replies)
          if @options[:limit].positive? && messages.length > @options[:limit]
            messages = [messages.first] + messages.last(@options[:limit] - 1)
          end
        else
          # For channel history, use oldest parameter if provided
          # Slack API oldest is exclusive - decrement slightly to include the target message
          oldest_adjusted = oldest ? adjust_timestamp(oldest, -0.000001) : nil
          response = api.history(channel: channel_id, limit: @options[:limit], oldest: oldest_adjusted)
          messages = response['messages'] || []
        end

        # Convert to model objects
        messages = messages.map { |m| Models::Message.from_api(m, channel_id: channel_id) }

        # Reverse to show oldest first
        messages.reverse
      end

      # Adjust a Slack timestamp by a small amount while preserving precision
      def adjust_timestamp(timestamp, delta)
        require 'bigdecimal'
        (BigDecimal(timestamp) + BigDecimal(delta.to_s)).to_s('F')
      end

      def fetch_all_thread_replies(api, channel_id, thread_ts)
        all_messages = []
        cursor = nil

        loop do
          response = api.replies(channel: channel_id, timestamp: thread_ts, limit: 200, cursor: cursor)
          page_messages = response['messages'] || []
          all_messages.concat(page_messages)

          debug("Fetched #{page_messages.length} messages, total: #{all_messages.length}")

          cursor = response.dig('response_metadata', 'next_cursor')
          break if cursor.nil? || cursor.empty? || !response['has_more']
        end

        # Deduplicate and sort by timestamp
        all_messages
          .uniq { |m| m['ts'] }
          .sort_by { |m| m['ts'].to_f }
      end

      def display_messages(messages, workspace, channel_id)
        formatter = runner.message_formatter
        opts = format_options.merge(channel_id: channel_id)

        messages.each_with_index do |message, index|
          display_single_message(formatter, message, workspace, opts)
          puts if index < messages.length - 1

          show_thread_replies(workspace, channel_id, message, opts) if should_show_thread?(message)
        end
      end

      def should_show_thread?(message)
        @options[:threads] && message.thread? && !message.reply?
      end

      def display_single_message(formatter, message, workspace, opts)
        formatted = formatter.format(message, workspace: workspace, options: opts)
        print_with_workspace_emoji(formatted, workspace)
      end

      def show_thread_replies(workspace, channel_id, parent_message, opts)
        api = runner.conversations_api(workspace.name)
        replies = fetch_all_thread_replies(api, channel_id, parent_message.ts)

        replies[1..].each { |reply_data| display_thread_reply(reply_data, workspace, channel_id, opts) }
      end

      def display_thread_reply(reply_data, workspace, channel_id, opts)
        reply = Models::Message.from_api(reply_data, channel_id: channel_id)
        formatted = runner.message_formatter.format(reply, workspace: workspace, options: opts)

        lines = formatted.lines
        print_with_workspace_emoji("  └ #{lines.first}", workspace)
        lines[1..].each { |line| print_with_workspace_emoji("    #{line}", workspace) }
      end

      # Print text, replacing workspace emoji codes with inline images when enabled
      def print_with_workspace_emoji(text, workspace)
        if @options[:workspace_emoji] && inline_images_supported?
          print_line_with_emoji_images(text, workspace)
        else
          puts text
        end
      end

      # Print a line, inserting inline images for workspace emoji
      def print_line_with_emoji_images(text, workspace)
        # Find all :emoji: codes that weren't replaced (workspace custom emoji)
        emoji_pattern = /:([a-zA-Z0-9_+-]+):/

        # Split text into parts, preserving emoji codes
        parts = text.split(emoji_pattern)

        parts.each_with_index do |part, i|
          if i.odd?
            # This is an emoji name (captured group)
            emoji_path = find_workspace_emoji(workspace.name, part)
            if emoji_path
              print_inline_image(emoji_path, height: 1)
              print ' ' unless in_tmux?
            else
              # Not a workspace emoji, print as-is
              print ":#{part}:"
            end
          else
            # Regular text
            print part
          end
        end
        puts
      end

      def find_workspace_emoji(workspace_name, emoji_name)
        return nil if emoji_name.empty?

        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir
        workspace_dir = File.join(emoji_dir, workspace_name)
        return nil unless Dir.exist?(workspace_dir)

        # Look for emoji file with any extension
        Dir.glob(File.join(workspace_dir, "#{emoji_name}.*")).first
      end
    end
  end
end
