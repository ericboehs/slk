# frozen_string_literal: true

require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Unread < Base
      def execute
        return show_help if show_help?

        case positional_args
        in ["clear", *rest]
          clear_unread(rest.first)
        in []
          show_unread
        else
          error("Unknown action: #{positional_args.first}")
          1
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(
          all: true, # Default to all workspaces
          muted: false,
          limit: 10,
          no_emoji: false,
          no_reactions: false,
          workspace_emoji: true, # Default to showing workspace emoji as images
          reaction_names: false
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when "--muted"
          @options[:muted] = true
        when "-n", "--limit"
          @options[:limit] = args.shift.to_i
        when "--no-emoji"
          @options[:no_emoji] = true
        when "--no-reactions"
          @options[:no_reactions] = true
        when "--no-workspace-emoji"
          @options[:workspace_emoji] = false
        when "--reaction-names"
          @options[:reaction_names] = true
        else
          remaining << arg
        end
      end

      def help_text
        help = Support::HelpFormatter.new("slk unread [action] [options]")
        help.description("View and manage unread messages (all workspaces by default).")

        help.section("ACTIONS") do |s|
          s.action("(none)", "Show unread messages")
          s.action("clear", "Mark all as read")
          s.action("clear #channel", "Mark specific channel as read")
        end

        help.section("OPTIONS") do |s|
          s.option("-n, --limit N", "Messages per channel (default: 10)")
          s.option("--muted", "Include/clear muted channels")
          s.option("--no-emoji", "Show :emoji: codes instead of unicode")
          s.option("--no-reactions", "Hide reactions")
          s.option("--no-workspace-emoji", "Disable workspace emoji images")
          s.option("--reaction-names", "Show reactions with user names")
          s.option("-w, --workspace", "Limit to specific workspace")
          s.option("--json", "Output as JSON")
          s.option("-q, --quiet", "Suppress output")
        end

        help.render
      end

      private

      def show_unread
        target_workspaces.each do |workspace|
          client = runner.client_api(workspace.name)
          conversations_api = runner.conversations_api(workspace.name)
          formatter = runner.message_formatter

          if @options[:all] || target_workspaces.size > 1
            puts output.bold(workspace.name)
          end

          counts = client.counts

          # Get muted channels from user prefs unless --muted flag is set
          muted_ids = @options[:muted] ? [] : runner.users_api(workspace.name).muted_channels

          # DMs first
          ims = counts["ims"] || []
          unread_ims = ims.select { |i| i["has_unreads"] }

          unread_ims.each do |im|
            mention_count = im["mention_count"] || 0
            user_name = get_dm_user_name(workspace, im["id"], conversations_api)
            puts
            puts output.bold("@#{user_name}") + (mention_count > 0 ? " (#{mention_count} mentions)" : "")
            puts
            show_channel_messages(workspace, im["id"], @options[:limit], conversations_api, formatter)
          end

          # Channels
          channels = counts["channels"] || []
          unreads = channels
            .select { |c| c["has_unreads"] || (c["mention_count"] || 0) > 0 }
            .reject { |c| muted_ids.include?(c["id"]) }

          if @options[:json]
            output_json({
              channels: unreads.map { |c| { id: c["id"], mentions: c["mention_count"] } },
              dms: unread_ims.map { |i| { id: i["id"], mentions: i["mention_count"] } }
            })
          else
            if unreads.empty? && unread_ims.empty?
              puts "No unread messages"
            else
              unreads.each do |channel|
                name = cache_store.get_channel_name(workspace.name, channel["id"]) || channel["id"]
                limit = @options[:limit]

                puts
                puts output.bold("##{name}") + " (showing last #{limit})"
                puts
                show_channel_messages(workspace, channel["id"], limit, conversations_api, formatter)
              end
            end

            # Show threads
            show_threads(workspace, formatter)
          end
        end

        0
      end

      def show_threads(workspace, formatter)
        threads_api = runner.threads_api(workspace.name)
        threads_response = threads_api.get_view(limit: 20)

        return unless threads_response["ok"]

        total_unreads = threads_response["total_unread_replies"] || 0
        return if total_unreads == 0

        threads = threads_response["threads"] || []

        puts
        puts output.bold("🧵 Threads") + " (#{total_unreads} unread replies)"
        puts

        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          workspace_emoji: @options[:workspace_emoji],
          reaction_names: @options[:reaction_names]
        }

        threads.each do |thread|
          unread_replies = thread["unread_replies"] || []
          next if unread_replies.empty?

          root_msg = thread["root_msg"] || {}
          channel_id = root_msg["channel"]
          conversation_label = resolve_conversation_label(workspace, channel_id)

          # Get root user name
          root_user = extract_user_from_message(root_msg, workspace)

          puts output.blue("  #{conversation_label}") + " - thread by " + output.bold(root_user)

          # Display unread replies (limit to @options[:limit])
          unread_replies.first(@options[:limit]).each do |reply|
            message = Models::Message.from_api(reply)
            puts "    #{formatter.format_simple(message, workspace: workspace, options: format_options)}"
          end

          puts
        end
      end

      def extract_user_from_message(msg, workspace)
        # Try user_profile embedded in message
        if msg["user_profile"]
          name = msg["user_profile"]["display_name"]
          name = msg["user_profile"]["real_name"] if name.to_s.empty?
          return name unless name.to_s.empty?
        end

        # Try username field
        return msg["username"] unless msg["username"].to_s.empty?

        # Try cache
        user_id = msg["user"] || msg["bot_id"]
        if user_id
          cached = cache_store.get_user(workspace.name, user_id)
          return cached if cached
        end

        user_id || "unknown"
      end

      def show_channel_messages(workspace, channel_id, limit, api, formatter)
        history = api.history(channel: channel_id, limit: limit)
        messages = (history["messages"] || []).reverse

        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          workspace_emoji: @options[:workspace_emoji],
          reaction_names: @options[:reaction_names]
        }

        messages.each do |msg|
          message = Models::Message.from_api(msg)
          puts formatter.format_simple(message, workspace: workspace, options: format_options)
        end
      rescue ApiError => e
        puts output.dim("  (Could not fetch messages: #{e.message})")
      end

      def clear_unread(channel_name)
        target_workspaces.each do |workspace|
          if channel_name
            # Clear specific channel
            channel_id = if channel_name.match?(/^[CDG][A-Z0-9]+$/)
              channel_name
            else
              name = channel_name.delete_prefix("#")
              cache_store.get_channel_id(workspace.name, name) ||
                resolve_channel(workspace, name)
            end

            api = runner.conversations_api(workspace.name)
            # Get latest message timestamp
            history = api.history(channel: channel_id, limit: 1)
            if (messages = history["messages"]) && messages.any?
              api.mark(channel: channel_id, ts: messages.first["ts"])
              success("Marked ##{channel_name} as read on #{workspace.name}")
            end
          else
            # Clear all
            client = runner.client_api(workspace.name)
            counts = client.counts

            # Get muted channels from user prefs unless --muted flag is set
            muted_ids = @options[:muted] ? [] : runner.users_api(workspace.name).muted_channels

            channels = counts["channels"] || []
            channels_cleared = 0
            channels.each do |channel|
              next unless channel["has_unreads"]
              next if muted_ids.include?(channel["id"])

              api = runner.conversations_api(workspace.name)
              begin
                history = api.history(channel: channel["id"], limit: 1)
                if (messages = history["messages"]) && messages.any?
                  api.mark(channel: channel["id"], ts: messages.first["ts"])
                  channels_cleared += 1
                end
              rescue ApiError
                # Skip channels we can't access
              end
            end

            # Also clear threads
            threads_api = runner.threads_api(workspace.name)
            threads_response = threads_api.get_view(limit: 50)
            threads_cleared = 0

            if threads_response["ok"]
              (threads_response["threads"] || []).each do |thread|
                unread_replies = thread["unread_replies"] || []
                next if unread_replies.empty?

                root_msg = thread["root_msg"] || {}
                channel_id = root_msg["channel"]
                thread_ts = root_msg["thread_ts"]
                latest_ts = unread_replies.map { |r| r["ts"] }.max

                begin
                  threads_api.mark(channel: channel_id, thread_ts: thread_ts, ts: latest_ts)
                  threads_cleared += 1
                rescue ApiError
                  # Skip threads we can't mark
                end
              end
            end

            success("Cleared #{channels_cleared} channels and #{threads_cleared} threads on #{workspace.name}")
          end
        end

        0
      end

      def get_dm_user_name(workspace, channel_id, conversations)
        # Try to get user from conversation info
        begin
          info = conversations.info(channel: channel_id)
          if info["ok"] && info["channel"]
            user_id = info["channel"]["user"]
            if user_id
              # Try cache first
              cached = cache_store.get_user(workspace.name, user_id)
              return cached if cached

              # Try users API lookup
              begin
                users_api = runner.users_api(workspace.name)
                user_info = users_api.info(user_id)
                if user_info["ok"] && user_info["user"]
                  profile = user_info["user"]["profile"] || {}
                  name = profile["display_name"]
                  name = profile["real_name"] if name.to_s.empty?
                  name = user_info["user"]["name"] if name.to_s.empty?
                  if name && !name.empty?
                    # Cache for future lookups
                    cache_store.set_user(workspace.name, user_id, name, persist: true)
                    return name
                  end
                end
              rescue ApiError
                # Fall through to user ID
              end

              return user_id
            end
          end
        rescue ApiError
          # Fall through to channel ID
        end

        channel_id
      end

      def resolve_conversation_label(workspace, channel_id)
        # DM channels start with D
        if channel_id.start_with?("D")
          conversations = runner.conversations_api(workspace.name)
          user_name = get_dm_user_name(workspace, channel_id, conversations)
          return "@#{user_name}"
        end

        # Try cache first
        cached_name = cache_store.get_channel_name(workspace.name, channel_id)
        return "##{cached_name}" if cached_name

        # Try API lookup
        begin
          conversations = runner.conversations_api(workspace.name)
          response = conversations.info(channel: channel_id)
          if response["ok"] && response["channel"]
            name = response["channel"]["name"]
            if name
              cache_store.set_channel(workspace.name, name, channel_id)
              return "##{name}"
            end
          end
        rescue ApiError
          # Fall through to channel ID
        end

        "##{channel_id}"
      end

      def resolve_channel(workspace, name)
        api = runner.conversations_api(workspace.name)
        response = api.list
        channels = response["channels"] || []
        channel = channels.find { |c| c["name"] == name }
        channel&.dig("id") || raise(ConfigError, "Channel not found: ##{name}")
      end
    end
  end
end
