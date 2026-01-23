# frozen_string_literal: true

require_relative '../support/help_formatter'
require_relative '../support/inline_images'

module Slk
  module Commands
    # Reads messages from channels, DMs, or threads
    # rubocop:disable Metrics/ClassLength
    class Messages < Base
      include Support::InlineImages

      # rubocop:disable Metrics/MethodLength
      def execute
        result = validate_options
        return result if result

        target = positional_args.first
        return missing_target_error unless target

        resolved = target_resolver.resolve(target, default_workspace: target_workspaces.first)
        fetch_and_display_messages(resolved)
      rescue ApiError => e
        error("Failed to fetch messages: #{e.message}")
        1
      rescue ArgumentError => e
        error(e.message)
        1
      end
      # rubocop:enable Metrics/MethodLength

      def missing_target_error
        error('Usage: slk messages <channel|@user|url>')
        1
      end

      def fetch_and_display_messages(resolved)
        apply_default_limit(resolved.msg_ts)
        messages = fetch_messages(resolved.workspace, resolved.channel_id, resolved.thread_ts, oldest: resolved.msg_ts)
        messages = enrich_reactions(messages, resolved.workspace, resolved.channel_id) if @options[:reaction_timestamps]

        output_messages(messages, resolved.workspace, resolved.channel_id)
        0
      end

      def output_messages(messages, workspace, channel_id)
        if @options[:json]
          output_json_messages(messages, workspace, channel_id)
        else
          display_messages(messages, workspace, channel_id)
        end
      end

      protected

      def default_options
        super.merge(
          limit: 500,
          limit_set: false,
          threads: false,
          workspace_emoji: false,
          since: nil
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-n', '--limit' then handle_limit_option(args)
        when '--since' then handle_since_option(args)
        when '--threads' then @options[:threads] = true
        when '--workspace-emoji' then @options[:workspace_emoji] = true
        else super
        end
      end

      def handle_since_option(args)
        value = args.shift
        raise ArgumentError, '--since requires a duration (1d, 7d, 1w, 1m) or date (YYYY-MM-DD)' unless value

        @options[:since] = value
      end

      def handle_limit_option(args)
        @options[:limit] = args.shift.to_i
        @options[:limit_set] = true
      end

      def help_text
        help = Support::HelpFormatter.new('slk messages <target> [options]')
        help.description('Read messages from a channel, DM, or thread.')
        add_target_section(help)
        add_options_section(help)
        help.render
      end

      def add_target_section(help)
        help.section('TARGET') do |s|
          s.item('#channel', 'Channel by name')
          s.item('channel', 'Channel by name (without #)')
          s.item('@user', 'Direct message with user')
          s.item('C123ABC', 'Channel by ID')
          s.item('<slack_url>', 'Slack message URL (returns message + subsequent)')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          add_message_options(s)
          add_formatting_options(s)
          add_common_options(s)
        end
      end

      def add_message_options(section)
        section.option('-n, --limit N', 'Number of messages (default: 500, or 50 for message URLs)')
        section.option('--since DURATION', 'Messages since duration (1d, 7d, 1w, 1m) or date (YYYY-MM-DD)')
        section.option('--threads', 'Show thread replies inline')
        section.option('--workspace-emoji', 'Show workspace emoji as inline images (experimental)')
      end

      def add_formatting_options(section)
        section.option('--no-emoji', 'Show :emoji: codes instead of unicode')
        section.option('--no-reactions', 'Hide reactions')
        section.option('--no-names', 'Skip user name lookups (faster)')
        section.option('--reaction-names', 'Show reactions with user names')
        section.option('--reaction-timestamps', 'Show when each person reacted')
        section.option('--width N', 'Wrap text at N columns (default: 72 on TTY, no wrap otherwise)')
        section.option('--no-wrap', 'Disable text wrapping')
      end

      def add_common_options(section)
        section.option('--json', 'Output as JSON')
        section.option('-w, --workspace', 'Specify workspace')
        section.option('-v, --verbose', 'Show debug information')
        section.option('-q, --quiet', 'Suppress output')
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
        raw = if thread_ts
                fetch_thread_messages(api, channel_id, thread_ts)
              else
                fetch_channel_history(api, channel_id, oldest)
              end

        raw.map { |m| Models::Message.from_api(m, channel_id: channel_id) }.reverse
      end

      def fetch_thread_messages(api, channel_id, thread_ts)
        messages = fetch_all_thread_replies(api, channel_id, thread_ts)
        apply_thread_limit(messages)
      end

      def apply_thread_limit(messages)
        return messages unless @options[:limit].positive? && messages.length > @options[:limit]

        [messages.first] + messages.last(@options[:limit] - 1)
      end

      def fetch_channel_history(api, channel_id, oldest)
        oldest_ts = determine_oldest_timestamp(oldest)
        response = api.history(channel: channel_id, limit: @options[:limit], oldest: oldest_ts)
        response['messages'] || []
      end

      def determine_oldest_timestamp(oldest_from_url)
        # URL-based oldest takes precedence
        return adjust_timestamp(oldest_from_url, -0.000001) if oldest_from_url

        # Otherwise use --since if provided
        return Support::DateParser.to_slack_timestamp(@options[:since]) if @options[:since]

        nil
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
          response, cursor = fetch_thread_page(api, channel_id, thread_ts, cursor)
          all_messages.concat(response)
          break if cursor.nil? || cursor.empty?
        end

        deduplicate_and_sort(all_messages)
      end

      def fetch_thread_page(api, channel_id, thread_ts, cursor)
        response = api.replies(channel: channel_id, timestamp: thread_ts, limit: 200, cursor: cursor)
        messages = response['messages'] || []
        debug("Fetched #{messages.length} messages")

        next_cursor = response['has_more'] ? response.dig('response_metadata', 'next_cursor') : nil
        [messages, next_cursor]
      end

      def deduplicate_and_sort(messages)
        messages.uniq { |m| m['ts'] }.sort_by { |m| m['ts'].to_f }
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
        emoji_pattern = /:([a-zA-Z0-9_+-]+):/
        parts = text.split(emoji_pattern)

        parts.each_with_index { |part, i| print_emoji_part(part, i, workspace) }
        puts
      end

      def print_emoji_part(part, index, workspace)
        if index.odd?
          print_emoji_or_code(part, workspace)
        else
          print part
        end
      end

      def print_emoji_or_code(emoji_name, workspace)
        emoji_path = find_workspace_emoji(workspace.name, emoji_name)
        if emoji_path
          print_inline_image(emoji_path, height: 1)
          print ' ' unless in_tmux?
        else
          print ":#{emoji_name}:"
        end
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
    # rubocop:enable Metrics/ClassLength
  end
end
