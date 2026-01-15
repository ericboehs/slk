# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Interactive review and dismissal of unread messages
    class Catchup < Base
      include Support::UserResolver

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
          client = runner.client_api(workspace.name)
          counts = client.counts
          conversations = runner.conversations_api(workspace.name)

          # Mark DMs as read
          ims = counts['ims'] || []
          dms_marked = 0

          ims.each do |im|
            next unless im['has_unreads']

            begin
              history = conversations.history(channel: im['id'], limit: 1)
              if (messages = history['messages']) && messages.any?
                conversations.mark(channel: im['id'], ts: messages.first['ts'])
                dms_marked += 1
              end
            rescue ApiError => e
              debug("Could not mark DM #{im['id']}: #{e.message}")
            end
          end

          # Mark channels as read
          channels = counts['channels'] || []
          channels_marked = 0

          channels.each do |channel|
            next unless channel['has_unreads']
            next if !@options[:muted] && channel['is_muted']

            begin
              history = conversations.history(channel: channel['id'], limit: 1)
              if (messages = history['messages']) && messages.any?
                conversations.mark(channel: channel['id'], ts: messages.first['ts'])
                channels_marked += 1
              end
            rescue ApiError => e
              debug("Could not mark channel #{channel['id']}: #{e.message}")
            end
          end

          # Mark threads as read
          threads_api = runner.threads_api(workspace.name)
          threads_response = threads_api.get_view(limit: 50)
          threads_marked = 0

          if threads_response['ok']
            (threads_response['threads'] || []).each do |thread|
              unread_replies = thread['unread_replies'] || []
              next if unread_replies.empty?

              root_msg = thread['root_msg'] || {}
              channel_id = root_msg['channel']
              thread_ts = root_msg['thread_ts']
              latest_ts = unread_replies.map { |r| r['ts'] }.max

              begin
                threads_api.mark(channel: channel_id, thread_ts: thread_ts, ts: latest_ts)
                threads_marked += 1
              rescue ApiError => e
                debug("Could not mark thread #{thread_ts} in #{channel_id}: #{e.message}")
              end
            end
          end

          success("Marked #{dms_marked} DMs, #{channels_marked} channels, " \
                  "and #{threads_marked} threads as read on #{workspace.name}")
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
        mentions = channel['mention_count'] || 0
        last_read = channel['last_read']
        latest_ts = channel['latest'] # Latest message timestamp for marking as read

        # Fetch only unread messages (after last_read timestamp)
        conversations = runner.conversations_api(workspace.name)
        history_opts = { channel: channel_id, limit: @options[:limit] }
        history_opts[:oldest] = last_read if last_read
        history = conversations.history(**history_opts)
        messages = (history['messages'] || []).reverse

        # Display header
        puts
        puts output.bold("[#{index + 1}/#{total}] ##{channel_name}")
        puts output.yellow("#{mentions} mentions") if mentions.positive?

        # Convert to model objects
        message_objects = messages.map { |msg| Models::Message.from_api(msg, channel_id: channel_id) }

        # Enrich with reaction timestamps if requested
        if @options[:reaction_timestamps]
          enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
          message_objects = enricher.enrich_messages(message_objects, channel_id)
        end

        # Display messages
        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          reaction_names: @options[:reaction_names],
          reaction_timestamps: @options[:reaction_timestamps]
        }

        message_objects.each do |message|
          formatted = runner.message_formatter.format_simple(message, workspace: workspace, options: format_options)
          puts "  #{formatted}"
        end

        # Prompt for action (loop until valid key)
        prompt = output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')
        loop do
          input = prompt_for_action(prompt)
          result = handle_channel_action(input, workspace, channel_id, latest_ts, conversations)
          return result if result
        end
      end

      def process_dm(workspace, im, index, total)
        channel_id = im['id']
        last_read = im['last_read']
        latest_ts = im['latest'] # Latest message timestamp for marking as read
        mention_count = im['mention_count'] || 0

        # Get user info from conversation
        conversations = runner.conversations_api(workspace.name)
        user_name = resolve_dm_user_name(workspace, channel_id, conversations)

        # Fetch only unread messages (after last_read timestamp)
        history_opts = { channel: channel_id, limit: @options[:limit] }
        history_opts[:oldest] = last_read if last_read
        history = conversations.history(**history_opts)
        messages = (history['messages'] || []).reverse

        # Display header
        puts
        puts output.bold("[#{index + 1}/#{total}] @#{user_name}")
        puts output.yellow("#{mention_count} mentions") if mention_count.positive?

        # Convert to model objects
        message_objects = messages.map { |msg| Models::Message.from_api(msg, channel_id: channel_id) }

        # Enrich with reaction timestamps if requested
        if @options[:reaction_timestamps]
          enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
          message_objects = enricher.enrich_messages(message_objects, channel_id)
        end

        # Display messages
        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          reaction_names: @options[:reaction_names],
          reaction_timestamps: @options[:reaction_timestamps]
        }

        message_objects.each do |message|
          formatted = runner.message_formatter.format_simple(message, workspace: workspace, options: format_options)
          puts "  #{formatted}"
        end

        # Prompt for action (loop until valid key)
        prompt = output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')
        loop do
          input = prompt_for_action(prompt)
          result = handle_channel_action(input, workspace, channel_id, latest_ts, conversations)
          return result if result
        end
      end

      def prompt_for_action(prompt)
        print "\n#{prompt} > "
        input = read_single_char
        puts
        input
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

        format_options = {
          no_emoji: @options[:no_emoji],
          no_reactions: @options[:no_reactions],
          workspace_emoji: @options[:workspace_emoji],
          reaction_names: @options[:reaction_names],
          reaction_timestamps: @options[:reaction_timestamps]
        }

        # Display header
        puts
        puts output.bold("[#{index + 1}/#{total}] 🧵 Threads (#{total_unreads} unread replies)")

        # Display threads and track for marking
        thread_mark_data = []

        threads.each do |thread|
          unread_replies = thread['unread_replies'] || []
          next if unread_replies.empty?

          root_msg = thread['root_msg'] || {}
          channel_id = root_msg['channel']
          thread_ts = root_msg['thread_ts']
          conversation_label = resolve_conversation_label(workspace, channel_id)

          # Get root user name
          root_user = extract_user_from_message(root_msg, workspace)

          puts "#{output.blue("  #{conversation_label}")} - thread by #{output.bold(root_user)}"

          # Convert to model objects
          message_objects = unread_replies.map { |reply| Models::Message.from_api(reply, channel_id: channel_id) }

          # Enrich with reaction timestamps if requested
          if @options[:reaction_timestamps]
            enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
            message_objects = enricher.enrich_messages(message_objects, channel_id)
          end

          # Display unread replies
          message_objects.each do |message|
            formatted = runner.message_formatter.format_simple(message, workspace: workspace, options: format_options)
            puts "    #{formatted}"
          end

          # Track latest reply ts for marking
          latest_ts = unread_replies.map { |r| r['ts'] }.max
          thread_mark_data << { channel: channel_id, thread_ts: thread_ts, ts: latest_ts }

          puts
        end

        # Prompt for action (loop until valid key)
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
        when 'q', "\u0003", "\u0004" # q, Ctrl-C, Ctrl-D
          :quit
        when 'r'
          # Mark all threads as read
          threads_api = runner.threads_api(workspace.name)
          marked = 0
          thread_mark_data.each do |data|
            threads_api.mark(channel: data[:channel], thread_ts: data[:thread_ts], ts: data[:ts])
            marked += 1
          rescue ApiError => e
            debug("Could not mark thread #{data[:thread_ts]} in #{data[:channel]}: #{e.message}")
          end
          success("Marked #{marked} thread(s) as read")
          :next
        when 'o'
          # Open first thread in Slack
          if thread_mark_data.any?
            first = thread_mark_data.first
            team_id = runner.client_api(workspace.name).team_id
            url = "slack://channel?team=#{team_id}&id=#{first[:channel]}&thread_ts=#{first[:thread_ts]}"
            system('open', url)
            success('Opened in Slack')
          end
          :next
        else
          print "\r#{output.red('Invalid key')} - #{output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')}"
          nil # Return nil to continue loop
        end
      end

      def read_single_char
        if $stdin.tty?
          $stdin.raw(&:readchar)
        else
          $stdin.gets&.chomp
        end
      rescue Interrupt
        'q'
      end
    end
  end
end
