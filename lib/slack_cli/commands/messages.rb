# frozen_string_literal: true

require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Messages < Base
      def execute
        return show_help if show_help?

        target = positional_args.first
        unless target
          error("Usage: slk messages <channel|@user|url>")
          return 1
        end

        workspace, channel_id, thread_ts = resolve_target(target)
        messages = fetch_messages(workspace, channel_id, thread_ts)

        if @options[:json]
          output_json(messages.map { |m| runner.message_formatter.format_json(m) })
        else
          display_messages(messages, workspace)
        end

        0
      rescue ApiError => e
        error("Failed to fetch messages: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(
          limit: 20,
          threads: false,
          no_emoji: false,
          no_reactions: false,
          no_names: false,
          workspace_emoji: true, # Default to showing workspace emoji as images
          reaction_names: false
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when "-n", "--limit"
          @options[:limit] = args.shift.to_i
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
        else
          remaining << arg
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
          s.item("<slack_url>", "Slack message URL")
        end

        help.section("OPTIONS") do |s|
          s.option("-n, --limit N", "Number of messages to show (default: 20)")
          s.option("--threads", "Show thread replies inline")
          s.option("--no-emoji", "Show :emoji: codes instead of unicode")
          s.option("--no-reactions", "Hide reactions")
          s.option("--no-names", "Skip user name lookups (faster)")
          s.option("--no-workspace-emoji", "Disable workspace emoji images")
          s.option("--reaction-names", "Show reactions with user names")
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
            return [ws, result.channel_id, result.thread_ts || result.ts]
          end
        end

        workspace = target_workspaces.first

        # Direct channel ID
        if target.match?(/^[CDG][A-Z0-9]+$/)
          return [workspace, target, nil]
        end

        # Channel by name
        if target.start_with?("#") || !target.start_with?("@")
          channel_name = target.delete_prefix("#")
          channel_id = resolve_channel(workspace, channel_name)
          return [workspace, channel_id, nil]
        end

        # DM by username
        if target.start_with?("@")
          username = target.delete_prefix("@")
          channel_id = resolve_dm(workspace, username)
          return [workspace, channel_id, nil]
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

      def fetch_messages(workspace, channel_id, thread_ts = nil)
        api = runner.conversations_api(workspace.name)

        if thread_ts
          response = api.replies(channel: channel_id, ts: thread_ts, limit: @options[:limit])
          messages = response["messages"] || []
        else
          response = api.history(channel: channel_id, limit: @options[:limit])
          messages = response["messages"] || []
        end

        # Convert to model objects
        messages = messages.map { |m| Models::Message.from_api(m) }

        # Reverse to show oldest first
        messages.reverse
      end

      def display_messages(messages, workspace)
        formatter = runner.message_formatter
        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          no_names: @options[:no_names],
          workspace_emoji: @options[:workspace_emoji],
          reaction_names: @options[:reaction_names]
        }

        messages.each_with_index do |message, index|
          formatted = formatter.format(message, workspace: workspace, options: format_options)
          puts formatted
          puts if index < messages.length - 1

          # Show thread replies if requested
          if @options[:threads] && message.has_thread? && !message.is_reply?
            show_thread_replies(workspace, message, format_options)
          end
        end
      end

      def show_thread_replies(workspace, parent_message, format_options)
        api = runner.conversations_api(workspace.name)

        # Get channel from context - we need to track this
        # For now, skip thread expansion (would need channel_id passed through)
        debug("Thread expansion not yet implemented")
      end
    end
  end
end
