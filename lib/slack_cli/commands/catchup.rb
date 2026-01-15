# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Interactive review and dismissal of unread messages
    class Catchup < Base
      include Support::UserResolver
      include Support::InteractivePrompt

      def execute
        result = validate_options
        return result if result

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
          all: true, # Default to all workspaces
          batch: false,
          muted: false,
          limit: 5,
          no_emoji: false,
          no_reactions: false,
          reaction_names: false,
          reaction_timestamps: false
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when '--batch'
          @options[:batch] = true
        when '--muted'
          @options[:muted] = true
        when '-n', '--limit'
          @options[:limit] = args.shift.to_i
        when '--no-emoji'
          @options[:no_emoji] = true
        when '--no-reactions'
          @options[:no_reactions] = true
        when '--reaction-names'
          @options[:reaction_names] = true
        when '--reaction-timestamps'
          @options[:reaction_timestamps] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk catchup [options]')
        help.description('Interactively review and dismiss unread messages (all workspaces by default).')

        help.section('OPTIONS') do |s|
          s.option('--batch', 'Non-interactive mode (mark all as read)')
          s.option('--muted', 'Include muted channels')
          s.option('-n, --limit N', 'Messages per channel (default: 5)')
          s.option('--no-emoji', 'Show :emoji: codes instead of unicode')
          s.option('--no-reactions', 'Hide reactions')
          s.option('--reaction-names', 'Show reactions with user names')
          s.option('--reaction-timestamps', 'Show when each person reacted')
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.section('INTERACTIVE KEYS') do |s|
          s.item('s / Enter', 'Skip channel')
          s.item('r', 'Mark as read and continue')
          s.item('o', 'Open in Slack')
          s.item('q', 'Quit')
        end

        help.render
      end

      private

      def batch_catchup
        target_workspaces.each do |workspace|
          marker = Services::UnreadMarker.new(
            conversations_api: runner.conversations_api(workspace.name),
            threads_api: runner.threads_api(workspace.name),
            client_api: runner.client_api(workspace.name),
            users_api: runner.users_api(workspace.name),
            on_debug: ->(msg) { debug(msg) }
          )

          counts = marker.mark_all(options: { muted: @options[:muted] })
          success("Marked #{counts[:dms]} DMs, #{counts[:channels]} channels, " \
                  "and #{counts[:threads]} threads as read on #{workspace.name}")
        end

        0
      end

      def interactive_catchup
        target_workspaces.each do |workspace|
          result = process_workspace(workspace)
          return 0 if result == :quit
        end

        puts
        success('Catchup complete!')
        0
      end

      def process_workspace(workspace)
        client = runner.client_api(workspace.name)
        counts = client.counts

        # Get muted channels from user prefs unless --muted flag is set
        muted_ids = @options[:muted] ? [] : runner.users_api(workspace.name).muted_channels

        # Get unread DMs
        ims = (counts['ims'] || [])
              .select { |i| i['has_unreads'] }

        # Get unread channels
        channels = (counts['channels'] || [])
                   .select { |c| c['has_unreads'] || (c['mention_count'] || 0).positive? }
                   .reject { |c| muted_ids.include?(c['id']) }

        # Check for unread threads
        threads_api = runner.threads_api(workspace.name)
        threads_response = threads_api.get_view(limit: 20)
        has_threads = threads_response['ok'] && (threads_response['total_unread_replies'] || 0).positive?

        total_items = ims.size + channels.size + (has_threads ? 1 : 0)

        if ims.empty? && channels.empty? && !has_threads
          puts "No unread messages in #{workspace.name}"
          return :continue
        end

        puts output.bold("\n#{workspace.name}: #{total_items} items with unreads\n")

        current_index = 0

        # Process DMs first
        ims.each do |im|
          result = process_dm(workspace, im, current_index, total_items)
          return :quit if result == :quit

          current_index += 1
        end

        # Process threads
        if has_threads
          result = process_threads(workspace, threads_response, current_index, total_items)
          return :quit if result == :quit

          current_index += 1
        end

        # Process channels
        channels.each do |channel|
          result = process_channel(workspace, channel, current_index, total_items)
          return :quit if result == :quit

          current_index += 1
        end

        :continue
      end

      def process_channel(workspace, channel, index, total)
        channel_id = channel['id']
        channel_name = cache_store.get_channel_name(workspace.name, channel_id) || channel_id
        label = "##{channel_name}"

        process_conversation(workspace, channel, index, total, label)
      end

      def process_dm(workspace, im, index, total)
        channel_id = im['id']
        conversations = runner.conversations_api(workspace.name)
        user_name = resolve_dm_user_name(workspace, channel_id, conversations)
        label = "@#{user_name}"

        process_conversation(workspace, im, index, total, label)
      end

      def process_conversation(workspace, item, index, total, label)
        channel_id = item['id']
        last_read = item['last_read']
        latest_ts = item['latest']
        mentions = item['mention_count'] || 0

        messages = fetch_unread_messages(workspace, channel_id, last_read)
        display_conversation_header(index, total, label, mentions)
        display_messages(workspace, messages, channel_id)
        prompt_conversation_action(workspace, channel_id, latest_ts)
      end

      def fetch_unread_messages(workspace, channel_id, last_read)
        conversations = runner.conversations_api(workspace.name)
        history_opts = { channel: channel_id, limit: @options[:limit] }
        history_opts[:oldest] = last_read if last_read
        history = conversations.history(**history_opts)
        (history['messages'] || []).reverse
      end

      def display_conversation_header(index, total, label, mentions)
        puts
        puts output.bold("[#{index + 1}/#{total}] #{label}")
        puts output.yellow("#{mentions} mentions") if mentions.positive?
      end

      def display_messages(workspace, raw_messages, channel_id)
        messages = raw_messages.map { |msg| Models::Message.from_api(msg, channel_id: channel_id) }
        messages = enrich_messages(workspace, messages, channel_id) if @options[:reaction_timestamps]

        messages.each do |message|
          formatted = runner.message_formatter.format_simple(message, workspace: workspace, options: format_options)
          puts "  #{formatted}"
        end
      end

      def enrich_messages(workspace, messages, channel_id)
        enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
        enricher.enrich_messages(messages, channel_id)
      end

      def format_options
        {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          reaction_names: @options[:reaction_names],
          reaction_timestamps: @options[:reaction_timestamps]
        }
      end

      def prompt_conversation_action(workspace, channel_id, latest_ts)
        conversations = runner.conversations_api(workspace.name)
        prompt = output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')
        loop do
          input = prompt_for_action(prompt)
          result = handle_channel_action(input, workspace, channel_id, latest_ts, conversations)
          return result if result
        end
      end

      def handle_channel_action(input, workspace, channel_id, latest_ts, conversations)
        case input&.downcase
        when 's', "\r", "\n", nil
          :next
        when 'q', "\u0003", "\u0004" # q, Ctrl-C, Ctrl-D
          :quit
        when 'r'
          # Mark as read using the latest message timestamp
          if latest_ts
            conversations.mark(channel: channel_id, ts: latest_ts)
            success('Marked as read')
          end
          :next
        when 'o'
          # Open in Slack (macOS)
          team_id = runner.client_api(workspace.name).team_id
          url = "slack://channel?team=#{team_id}&id=#{channel_id}"
          system('open', url)
          success('Opened in Slack')
          :next
        else
          print "\r#{output.red('Invalid key')} - #{output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')}"
          nil # Return nil to continue loop
        end
      end

      def process_threads(workspace, threads_response, index, total)
        total_unreads = threads_response['total_unread_replies'] || 0
        threads = threads_response['threads'] || []

        puts
        puts output.bold("[#{index + 1}/#{total}] 🧵 Threads (#{total_unreads} unread replies)")

        thread_mark_data = threads.filter_map { |thread| display_thread(workspace, thread) }

        prompt_threads_action(workspace, thread_mark_data)
      end

      def display_thread(workspace, thread)
        unread_replies = thread['unread_replies'] || []
        return nil if unread_replies.empty?

        root_msg = thread['root_msg'] || {}
        channel_id = root_msg['channel']
        thread_ts = root_msg['thread_ts']
        conversation_label = resolve_conversation_label(workspace, channel_id)
        root_user = extract_user_from_message(root_msg, workspace)

        puts "#{output.blue("  #{conversation_label}")} - thread by #{output.bold(root_user)}"
        display_thread_replies(workspace, unread_replies, channel_id)
        puts

        latest_ts = unread_replies.map { |r| r['ts'] }.max
        { channel: channel_id, thread_ts: thread_ts, ts: latest_ts }
      end

      def display_thread_replies(workspace, replies, channel_id)
        messages = replies.map { |reply| Models::Message.from_api(reply, channel_id: channel_id) }
        messages = enrich_messages(workspace, messages, channel_id) if @options[:reaction_timestamps]

        messages.each do |message|
          formatted = runner.message_formatter.format_simple(message, workspace: workspace, options: format_options)
          puts "    #{formatted}"
        end
      end

      def prompt_threads_action(workspace, thread_mark_data)
        prompt = output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')
        loop do
          input = prompt_for_action(prompt)
          result = handle_threads_action(input, workspace, thread_mark_data)
          return result if result
        end
      end

      def handle_threads_action(input, workspace, thread_mark_data)
        case input&.downcase
        when 's', "\r", "\n", nil
          :next
        when 'q', "\u0003", "\u0004"
          :quit
        when 'r'
          mark_threads_as_read(workspace, thread_mark_data)
          :next
        when 'o'
          open_first_thread(workspace, thread_mark_data)
          :next
        else
          print "\r#{output.red('Invalid key')} - #{output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')}"
          nil
        end
      end

      def mark_threads_as_read(workspace, thread_mark_data)
        threads_api = runner.threads_api(workspace.name)
        marked = 0
        thread_mark_data.each do |data|
          threads_api.mark(channel: data[:channel], thread_ts: data[:thread_ts], ts: data[:ts])
          marked += 1
        rescue ApiError => e
          debug("Could not mark thread #{data[:thread_ts]} in #{data[:channel]}: #{e.message}")
        end
        success("Marked #{marked} thread(s) as read")
      end

      def open_first_thread(workspace, thread_mark_data)
        return unless thread_mark_data.any?

        first = thread_mark_data.first
        team_id = runner.client_api(workspace.name).team_id
        url = "slack://channel?team=#{team_id}&id=#{first[:channel]}&thread_ts=#{first[:thread_ts]}"
        system('open', url)
        success('Opened in Slack')
      end
    end
  end
end
