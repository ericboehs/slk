# frozen_string_literal: true

module SlackCli
  module Commands
    class Catchup < Base
      def execute
        return show_help if show_help?

        if @options[:batch]
          batch_catchup
        else
          interactive_catchup
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(
          batch: false,
          muted: false,
          limit: 5
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when "--batch"
          @options[:batch] = true
        when "--muted"
          @options[:muted] = true
        when "-n", "--limit"
          @options[:limit] = args.shift.to_i
        else
          remaining << arg
        end
      end

      def help_text
        <<~HELP
          USAGE: slack catchup [options]

          Interactively review and dismiss unread messages.

          OPTIONS:
            --batch           Non-interactive mode (mark all as read)
            --muted           Include muted channels
            -n, --limit N     Messages per channel (default: 5)
            -w, --workspace   Specify workspace
            --all             Process all workspaces
            -q, --quiet       Suppress output

          INTERACTIVE KEYS:
            Enter / n         Next channel
            m                 Mark as read and continue
            r                 Show more messages
            o                 Open in Slack
            q                 Quit
        HELP
      end

      private

      def batch_catchup
        target_workspaces.each do |workspace|
          client = runner.client_api(workspace.name)
          counts = client.counts
          conversations = runner.conversations_api(workspace.name)

          channels = counts["channels"] || []
          processed = 0

          channels.each do |channel|
            next unless channel["has_unreads"]
            next if !@options[:muted] && channel["is_muted"]

            begin
              history = conversations.history(channel: channel["id"], limit: 1)
              if (messages = history["messages"]) && messages.any?
                conversations.mark(channel: channel["id"], ts: messages.first["ts"])
                processed += 1
              end
            rescue ApiError
              # Skip channels we can't access
            end
          end

          success("Marked #{processed} channels as read on #{workspace.name}")
        end

        0
      end

      def interactive_catchup
        target_workspaces.each do |workspace|
          result = process_workspace(workspace)
          return result if result == :quit
        end

        puts
        success("Catchup complete!")
        0
      end

      def process_workspace(workspace)
        client = runner.client_api(workspace.name)
        counts = client.counts

        channels = (counts["channels"] || [])
          .select { |c| c["has_unreads"] || (c["mention_count"] || 0) > 0 }
          .reject { |c| !@options[:muted] && c["is_muted"] }

        if channels.empty?
          puts "No unread messages in #{workspace.name}"
          return :continue
        end

        puts output.bold("\n#{workspace.name}: #{channels.size} channels with unreads\n")

        channels.each_with_index do |channel, index|
          result = process_channel(workspace, channel, index, channels.size)
          return :quit if result == :quit
        end

        :continue
      end

      def process_channel(workspace, channel, index, total)
        channel_id = channel["id"]
        channel_name = cache_store.get_channel_name(workspace.name, channel_id) || channel_id
        mentions = channel["mention_count"] || 0

        puts output.bold("\n[#{index + 1}/#{total}] ##{channel_name}")
        puts output.yellow("#{mentions} mentions") if mentions > 0

        # Fetch recent messages
        conversations = runner.conversations_api(workspace.name)
        history = conversations.history(channel: channel_id, limit: @options[:limit])
        messages = (history["messages"] || []).reverse

        # Display messages
        messages.each do |msg|
          message = Models::Message.from_api(msg)
          formatted = runner.message_formatter.format_simple(message, workspace: workspace)
          puts "  #{formatted}"
        end

        # Interactive prompt
        loop do
          print "\n#{output.cyan("[n]ext  [m]ark read  [r]efresh  [o]pen  [q]uit")} > "

          input = read_single_char
          puts

          case input&.downcase
          when "n", "\r", "\n", nil
            return :next
          when "m"
            # Mark as read
            if messages.any?
              conversations.mark(channel: channel_id, ts: messages.last["ts"])
              success("Marked as read")
            end
            return :next
          when "r"
            # Refresh/show more
            @options[:limit] += 5
            return process_channel(workspace, channel, index, total)
          when "o"
            # Open in Slack (macOS)
            url = "slack://channel?team=#{workspace.name}&id=#{channel_id}"
            system("open", url)
          when "q"
            return :quit
          end
        end
      end

      def read_single_char
        if $stdin.tty?
          $stdin.raw { |io| io.readchar }
        else
          $stdin.gets&.chomp
        end
      rescue Interrupt
        "q"
      end
    end
  end
end
