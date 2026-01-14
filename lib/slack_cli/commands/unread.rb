# frozen_string_literal: true

require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Unread < Base
      include Support::UserResolver

      def execute
        result = validate_options
        return result if result

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
          reaction_names: false,
          reaction_timestamps: false
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
        when "--reaction-names"
          @options[:reaction_names] = true
        when "--reaction-timestamps"
          @options[:reaction_timestamps] = true
        else
          super
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
          s.option("--reaction-names", "Show reactions with user names")
          s.option("--reaction-timestamps", "Show when each person reacted")
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
            user_name = resolve_dm_user_name(workspace, im["id"], conversations_api)
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
            message = Models::Message.from_api(reply, channel_id: channel_id)
            puts "    #{formatter.format_simple(message, workspace: workspace, options: format_options)}"
          end

          puts
        end
      end

      def show_channel_messages(workspace, channel_id, limit, api, formatter)
        history = api.history(channel: channel_id, limit: limit)
        raw_messages = (history["messages"] || []).reverse

        # Convert to model objects
        messages = raw_messages.map { |msg| Models::Message.from_api(msg, channel_id: channel_id) }

        # Enrich with reaction timestamps if requested
        if @options[:reaction_timestamps]
          enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
          messages = enricher.enrich_messages(messages, channel_id)
        end

        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          reaction_names: @options[:reaction_names],
          reaction_timestamps: @options[:reaction_timestamps]
        }

        messages.each do |message|
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
              rescue ApiError => e
                debug("Could not clear channel #{channel["id"]}: #{e.message}")
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
                rescue ApiError => e
                  debug("Could not mark thread #{thread_ts} in #{channel_id}: #{e.message}")
                end
              end
            end

            success("Cleared #{channels_cleared} channels and #{threads_cleared} threads on #{workspace.name}")
          end
        end

        0
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
