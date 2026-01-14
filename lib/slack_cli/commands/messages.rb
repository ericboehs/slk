# frozen_string_literal: true

require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Messages < Base
      def execute
        result = validate_options
        return result if result

        target = positional_args.first
        unless target
          error("Usage: slk messages <channel|@user|url>")
          return 1
        end

        workspace, channel_id, thread_ts, msg_ts = resolve_target(target)

        # Apply default limits based on target type
        apply_default_limit(msg_ts)

        messages = fetch_messages(workspace, channel_id, thread_ts, oldest: msg_ts)

        # Enrich with reaction timestamps if requested
        if @options[:reaction_timestamps]
          enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
          messages = enricher.enrich_messages(messages, channel_id)
        end

        if @options[:json]
          format_options = {
            no_names: @options[:no_names],
            reaction_timestamps: @options[:reaction_timestamps]
          }
          output_json(messages.map { |m| runner.message_formatter.format_json(m, workspace: workspace, options: format_options) })
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
          no_emoji: false,
          no_reactions: false,
          no_names: false,
          workspace_emoji: true, # Default to showing workspace emoji as images
          reaction_names: false,
          reaction_timestamps: false
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when "-n", "--limit"
          @options[:limit] = args.shift.to_i
          @options[:limit_set] = true
        when "--threads"
          @options[:threads] = true
        when "--no-emoji"
          @options[:no_emoji] = true
        when "--no-reactions"
          @options[:no_reactions] = true
        when "--no-names"
          @options[:no_names] = true
        when "--no-workspace-emoji"
          @options[:workspace_emoji] = false
        when "--reaction-names"
          @options[:reaction_names] = true
        when "--reaction-timestamps"
          @options[:reaction_timestamps] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new("slk messages <target> [options]")
        help.description("Read messages from a channel, DM, or thread.")

        help.section("TARGET") do |s|
          s.item("#channel", "Channel by name")
          s.item("channel", "Channel by name (without #)")
          s.item("@user", "Direct message with user")
          s.item("C123ABC", "Channel by ID")
          s.item("<slack_url>", "Slack message URL (returns message + subsequent)")
        end

        help.section("OPTIONS") do |s|
          s.option("-n, --limit N", "Number of messages (default: 500, or 50 for message URLs)")
          s.option("--threads", "Show thread replies inline")
          s.option("--no-emoji", "Show :emoji: codes instead of unicode")
          s.option("--no-reactions", "Hide reactions")
          s.option("--no-names", "Skip user name lookups (faster)")
          s.option("--no-workspace-emoji", "Disable workspace emoji images")
          s.option("--reaction-names", "Show reactions with user names")
          s.option("--reaction-timestamps", "Show when each person reacted")
          s.option("--width N", "Wrap text at N columns (default: 72 on TTY, no wrap otherwise)")
          s.option("--no-wrap", "Disable text wrapping")
          s.option("--json", "Output as JSON")
          s.option("-w, --workspace", "Specify workspace")
          s.option("-v, --verbose", "Show debug information")
          s.option("-q, --quiet", "Suppress output")
        end

        help.render
      end

      private

      def resolve_target(target)
        url_parser = Support::SlackUrlParser.new

        # Check if it's a Slack URL
        if url_parser.slack_url?(target)
          result = url_parser.parse(target)
          if result
            ws = runner.workspace(result.workspace)
            # thread_ts means it's a thread, msg_ts means start from that message
            if result.thread?
              return [ws, result.channel_id, result.thread_ts, nil]
            else
              return [ws, result.channel_id, nil, result.msg_ts]
            end
          end
        end

        workspace = target_workspaces.first

        # Direct channel ID
        if target.match?(/^[CDG][A-Z0-9]+$/)
          return [workspace, target, nil, nil]
        end

        # Channel by name
        if target.start_with?("#") || !target.start_with?("@")
          channel_name = target.delete_prefix("#")
          channel_id = resolve_channel(workspace, channel_name)
          return [workspace, channel_id, nil, nil]
        end

        # DM by username
        if target.start_with?("@")
          username = target.delete_prefix("@")
          channel_id = resolve_dm(workspace, username)
          return [workspace, channel_id, nil, nil]
        end

        raise ConfigError, "Could not resolve target: #{target}"
      end

      def resolve_channel(workspace, name)
        # Check cache first
        cached = cache_store.get_channel_id(workspace.name, name)
        return cached if cached

        # Search via API
        api = runner.conversations_api(workspace.name)
        response = api.list

        channels = response["channels"] || []
        channel = channels.find { |c| c["name"] == name }

        if channel
          cache_store.set_channel(workspace.name, name, channel["id"])
          return channel["id"]
        end

        raise ConfigError, "Channel not found: ##{name}"
      end

      def resolve_dm(workspace, username)
        # Find user ID
        user_id = find_user_id(workspace, username)
        raise ConfigError, "User not found: @#{username}" unless user_id

        # Open DM
        api = runner.conversations_api(workspace.name)
        response = api.open(users: user_id)
        response.dig("channel", "id")
      end

      def find_user_id(workspace, username)
        # Check cache
        # Note: We need reverse lookup, which cache_store doesn't support directly
        # For now, fetch user list and search

        api = runner.users_api(workspace.name)
        response = api.list

        users = response["members"] || []
        user = users.find do |u|
          u["name"] == username ||
            u.dig("profile", "display_name") == username ||
            u.dig("profile", "real_name") == username
        end

        user&.dig("id")
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
          if @options[:limit] > 0 && messages.length > @options[:limit]
            messages = [messages.first] + messages.last(@options[:limit] - 1)
          end
        else
          # For channel history, use oldest parameter if provided
          # Slack API oldest is exclusive - decrement slightly to include the target message
          oldest_adjusted = oldest ? adjust_timestamp(oldest, -0.000001) : nil
          response = api.history(channel: channel_id, limit: @options[:limit], oldest: oldest_adjusted)
          messages = response["messages"] || []
        end

        # Convert to model objects
        messages = messages.map { |m| Models::Message.from_api(m, channel_id: channel_id) }

        # Reverse to show oldest first
        messages.reverse
      end

      # Adjust a Slack timestamp by a small amount while preserving precision
      def adjust_timestamp(ts, delta)
        require 'bigdecimal'
        (BigDecimal(ts) + BigDecimal(delta.to_s)).to_s('F')
      end

      def fetch_all_thread_replies(api, channel_id, thread_ts)
        all_messages = []
        cursor = nil

        loop do
          response = api.replies(channel: channel_id, ts: thread_ts, limit: 200, cursor: cursor)
          page_messages = response["messages"] || []
          all_messages.concat(page_messages)

          debug("Fetched #{page_messages.length} messages, total: #{all_messages.length}")

          cursor = response.dig("response_metadata", "next_cursor")
          break if cursor.nil? || cursor.empty? || !response["has_more"]
        end

        # Deduplicate and sort by timestamp
        all_messages
          .uniq { |m| m["ts"] }
          .sort_by { |m| m["ts"].to_f }
      end

      def display_messages(messages, workspace, channel_id)
        formatter = runner.message_formatter
        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          no_names: @options[:no_names],
          workspace_emoji: @options[:workspace_emoji],
          reaction_names: @options[:reaction_names],
          width: @options[:width]
        }

        messages.each_with_index do |message, index|
          formatted = formatter.format(message, workspace: workspace, options: format_options)
          puts formatted
          puts if index < messages.length - 1

          # Show thread replies if requested
          if @options[:threads] && message.has_thread? && !message.is_reply?
            show_thread_replies(workspace, channel_id, message, format_options)
          end
        end
      end

      def show_thread_replies(workspace, channel_id, parent_message, format_options)
        api = runner.conversations_api(workspace.name)
        formatter = runner.message_formatter

        # Fetch all replies with pagination
        replies = fetch_all_thread_replies(api, channel_id, parent_message.ts)

        # Skip the parent message (first one) and show replies
        replies[1..].each do |reply_data|
          reply = Models::Message.from_api(reply_data, channel_id: channel_id)
          formatted = formatter.format(reply, workspace: workspace, options: format_options)

          # Indent multiline messages so continuation lines align with the first line
          lines = formatted.lines
          first_line = "  └ #{lines.first}"
          continuation_lines = lines[1..].map { |line| "    #{line}" }

          puts first_line
          continuation_lines.each { |line| puts line }
        end
      end
    end
  end
end
