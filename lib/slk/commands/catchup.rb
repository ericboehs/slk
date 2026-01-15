# frozen_string_literal: true

require_relative '../support/help_formatter'

module Slk
  module Commands
    # Interactive review and dismissal of unread messages
    # rubocop:disable Metrics/ClassLength
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
          limit: 5
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
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk catchup [options]')
        help.description('Interactively review and dismiss unread messages (all workspaces by default).')
        add_options_section(help)
        add_keys_section(help)
        help.render
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          add_primary_options(s)
          add_formatting_options(s)
        end
      end

      def add_primary_options(section)
        section.option('--batch', 'Non-interactive mode (mark all as read)')
        section.option('--muted', 'Include muted channels')
        section.option('-n, --limit N', 'Messages per channel (default: 5)')
      end

      def add_formatting_options(section)
        section.option('--no-emoji', 'Show :emoji: codes instead of unicode')
        section.option('--no-reactions', 'Hide reactions')
        section.option('--reaction-names', 'Show reactions with user names')
        section.option('--reaction-timestamps', 'Show when each person reacted')
        section.option('-w, --workspace', 'Limit to specific workspace')
        section.option('-q, --quiet', 'Suppress output')
      end

      def add_keys_section(help)
        help.section('INTERACTIVE KEYS') do |s|
          s.item('s / Enter', 'Skip channel')
          s.item('r', 'Mark as read and continue')
          s.item('o', 'Open in Slack')
          s.item('q', 'Quit')
        end
      end

      private

      def batch_catchup
        target_workspaces.each { |ws| batch_mark_workspace(ws) }
        0
      end

      def batch_mark_workspace(workspace)
        marker = build_unread_marker(workspace)
        counts = marker.mark_all(options: { muted: @options[:muted] })
        success("Marked #{counts[:dms]} DMs, #{counts[:channels]} channels, " \
                "and #{counts[:threads]} threads as read on #{workspace.name}")
      end

      def build_unread_marker(workspace)
        Services::UnreadMarker.new(
          conversations_api: runner.conversations_api(workspace.name),
          threads_api: runner.threads_api(workspace.name),
          client_api: runner.client_api(workspace.name),
          users_api: runner.users_api(workspace.name),
          on_debug: ->(msg) { debug(msg) }
        )
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
        items = gather_unread_items(workspace)

        if items[:empty]
          puts "No unread messages in #{workspace.name}"
          return :continue
        end

        puts output.bold("\n#{workspace.name}: #{items[:total]} items with unreads\n")
        process_all_items(workspace, items)
      end

      def gather_unread_items(workspace)
        counts = runner.client_api(workspace.name).counts
        ims = filter_unread_ims(counts['ims'] || [])
        channels = filter_unread_channels(workspace, counts['channels'] || [])
        threads_response = fetch_unread_threads(workspace)

        build_items_result(ims, channels, threads_response)
      end

      def build_items_result(ims, channels, threads_response)
        {
          ims: ims, channels: channels, threads_response: threads_response,
          total: ims.size + channels.size + (threads_response ? 1 : 0),
          empty: ims.empty? && channels.empty? && !threads_response
        }
      end

      def filter_unread_ims(ims)
        ims.select { |i| i['has_unreads'] }
      end

      def filter_unread_channels(workspace, channels)
        muted_ids = @options[:muted] ? [] : runner.users_api(workspace.name).muted_channels
        channels
          .select { |c| c['has_unreads'] || (c['mention_count'] || 0).positive? }
          .reject { |c| muted_ids.include?(c['id']) }
      end

      def fetch_unread_threads(workspace)
        response = runner.threads_api(workspace.name).get_view(limit: 20)
        response if response['ok'] && (response['total_unread_replies'] || 0).positive?
      end

      def process_all_items(workspace, items)
        index = { current: 0, total: items[:total] }

        return :quit if process_dms(workspace, items[:ims], index)
        return :quit if items[:threads_response] && process_threads_item(workspace, items[:threads_response], index)
        return :quit if process_channels(workspace, items[:channels], index)

        :continue
      end

      # rubocop:disable Naming/PredicateMethod
      def process_dms(workspace, ims, index)
        ims.each do |im|
          return true if process_dm(workspace, im, index[:current], index[:total]) == :quit

          index[:current] += 1
        end
        false
      end

      def process_channels(workspace, channels, index)
        channels.each do |channel|
          return true if process_channel(workspace, channel, index[:current], index[:total]) == :quit

          index[:current] += 1
        end
        false
      end

      def process_threads_item(workspace, threads_response, index)
        result = process_threads(workspace, threads_response, index[:current], index[:total])
        index[:current] += 1
        result == :quit
      end
      # rubocop:enable Naming/PredicateMethod

      def process_channel(workspace, channel, index, total)
        channel_id = channel['id']
        channel_name = cache_store.get_channel_name(workspace.name, channel_id) || channel_id
        label = "##{channel_name}"

        process_conversation(workspace, channel, index, total, label)
      end

      def process_dm(workspace, dm_item, index, total)
        channel_id = dm_item['id']
        conversations = runner.conversations_api(workspace.name)
        user_name = resolve_dm_user_name(workspace, channel_id, conversations)
        label = "@#{user_name}"

        process_conversation(workspace, dm_item, index, total, label)
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
        when 's', "\r", "\n", nil then :next
        when 'q', "\u0003", "\u0004" then :quit
        when 'r' then mark_channel_read(conversations, channel_id, latest_ts)
        when 'o' then open_channel_in_slack(workspace, channel_id)
        else
          print_invalid_key
          nil
        end
      end

      def mark_channel_read(conversations, channel_id, latest_ts)
        if latest_ts
          conversations.mark(channel: channel_id, timestamp: latest_ts)
          success('Marked as read')
        end
        :next
      end

      def open_channel_in_slack(workspace, channel_id)
        team_id = runner.client_api(workspace.name).team_id
        system('open', "slack://channel?team=#{team_id}&id=#{channel_id}")
        success('Opened in Slack')
        :next
      end

      def print_invalid_key
        print "\r#{output.red('Invalid key')} - #{output.cyan('[s]kip  [r]ead  [o]pen  [q]uit')}"
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
        print_thread_header(workspace, root_msg)
        display_thread_replies(workspace, unread_replies, root_msg['channel'])
        puts

        build_thread_mark_data(root_msg, unread_replies)
      end

      def print_thread_header(workspace, root_msg)
        label = resolve_conversation_label(workspace, root_msg['channel'])
        user = extract_user_from_message(root_msg, workspace)
        puts "#{output.blue("  #{label}")} - thread by #{output.bold(user)}"
      end

      def build_thread_mark_data(root_msg, unread_replies)
        {
          channel: root_msg['channel'],
          thread_ts: root_msg['thread_ts'],
          ts: unread_replies.map { |r| r['ts'] }.max
        }
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
        when 's', "\r", "\n", nil then :next
        when 'q', "\u0003", "\u0004" then :quit
        when 'r' then handle_mark_threads(workspace, thread_mark_data)
        when 'o' then handle_open_threads(workspace, thread_mark_data)
        else handle_invalid_key
        end
      end

      def handle_mark_threads(workspace, thread_mark_data)
        mark_threads_as_read(workspace, thread_mark_data)
        :next
      end

      def handle_open_threads(workspace, thread_mark_data)
        open_first_thread(workspace, thread_mark_data)
        :next
      end

      def handle_invalid_key
        print_invalid_key
        nil
      end

      def mark_threads_as_read(workspace, thread_mark_data)
        threads_api = runner.threads_api(workspace.name)
        marked = 0
        thread_mark_data.each do |data|
          threads_api.mark(channel: data[:channel], thread_ts: data[:thread_ts], timestamp: data[:ts])
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
    # rubocop:enable Metrics/ClassLength
  end
end
