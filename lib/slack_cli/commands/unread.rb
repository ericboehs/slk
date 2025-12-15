# frozen_string_literal: true

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
          muted: false,
          limit: 10,
          no_emoji: false,
          no_reactions: false,
          workspace_emoji: false,
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
        when "--workspace-emoji"
          @options[:workspace_emoji] = true
        when "--reaction-names"
          @options[:reaction_names] = true
        else
          remaining << arg
        end
      end

      def help_text
        <<~HELP
          USAGE: slk unread [action] [options]

          View and manage unread messages.

          ACTIONS:
            (none)            Show unread messages
            clear             Mark all as read
            clear #channel    Mark specific channel as read

          OPTIONS:
            -n, --limit N     Messages per channel (default: 10)
            --muted           Include/clear muted channels
            --no-emoji        Show :emoji: codes instead of unicode
            --no-reactions    Hide reactions
            --workspace-emoji Show workspace custom emoji as images
            --reaction-names  Show reactions with user names
            -w, --workspace   Specify workspace
            --all             Apply to all workspaces
            --json            Output as JSON
            -q, --quiet       Suppress output
        HELP
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

          # DMs first
          ims = counts["ims"] || []
          unread_ims = ims.select { |i| (i["dm_count"] || 0) > 0 }

          unread_ims.each do |im|
            count = im["dm_count"] || 0
            user_name = cache_store.get_user_name(workspace.name, im["user_id"]) || "DM"
            limit = [@options[:limit], count].min
            puts
            puts output.bold("@#{user_name} (#{count} unread)")
            puts
            show_channel_messages(workspace, im["id"], limit, conversations_api, formatter)
          end

          # Channels
          channels = counts["channels"] || []
          unreads = channels.select { |c| c["has_unreads"] || (c["mention_count"] || 0) > 0 }

          if @options[:json]
            output_json({
              channels: unreads.map { |c| { id: c["id"], mentions: c["mention_count"] } },
              dms: unread_ims.map { |i| { id: i["id"], count: i["dm_count"] } }
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
          end
        end

        0
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

            channels = counts["channels"] || []
            channels.each do |channel|
              next unless channel["has_unreads"]
              next if !@options[:muted] && channel["is_muted"]

              api = runner.conversations_api(workspace.name)
              begin
                history = api.history(channel: channel["id"], limit: 1)
                if (messages = history["messages"]) && messages.any?
                  api.mark(channel: channel["id"], ts: messages.first["ts"])
                end
              rescue ApiError
                # Skip channels we can't access
              end
            end

            success("Cleared unread on #{workspace.name}")
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
