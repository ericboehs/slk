# frozen_string_literal: true

require_relative '../support/help_formatter'

module Slk
  module Commands
    # Views and manages unread messages across workspaces
    # rubocop:disable Metrics/ClassLength
    class Unread < Base
      include Support::UserResolver

      def execute
        result = validate_options
        return result if result

        dispatch_action
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      private

      def dispatch_action
        case positional_args
        in ['clear', *rest] then clear_unread(rest.first)
        in [] then show_unread
        else unknown_action
        end
      end

      def unknown_action
        error("Unknown action: #{positional_args.first}")
        1
      end

      protected

      def default_options
        super.merge(
          all: true, # Default to all workspaces
          muted: false,
          limit: 10
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when '--muted'
          @options[:muted] = true
        when '-n', '--limit'
          @options[:limit] = args.shift.to_i
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk unread [action] [options]')
        help.description('View and manage unread messages (all workspaces by default).')
        add_actions_section(help)
        add_options_section(help)
        help.render
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('(none)', 'Show unread messages')
          s.action('clear', 'Mark all as read')
          s.action('clear #channel', 'Mark specific channel as read')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          add_core_options(s)
          add_formatting_options(s)
        end
      end

      def add_core_options(section)
        section.option('-n, --limit N', 'Messages per channel (default: 10)')
        section.option('--muted', 'Include/clear muted channels')
        section.option('-w, --workspace', 'Limit to specific workspace')
        section.option('--json', 'Output as JSON')
        section.option('-q, --quiet', 'Suppress output')
      end

      def add_formatting_options(section)
        section.option('--no-emoji', 'Show :emoji: codes instead of unicode')
        section.option('--no-reactions', 'Hide reactions')
        section.option('--reaction-names', 'Show reactions with user names')
        section.option('--reaction-timestamps', 'Show when each person reacted')
      end

      private

      def show_unread
        target_workspaces.each do |workspace|
          puts output.bold(workspace.name) if @options[:all] || target_workspaces.size > 1

          unread_data = fetch_unread_data(workspace)

          if @options[:json]
            output_unread_json(workspace, unread_data)
          else
            display_unread(workspace, unread_data)
          end
        end

        0
      end

      def fetch_unread_data(workspace)
        counts = runner.client_api(workspace.name).counts
        muted_ids = fetch_muted_ids(workspace)

        {
          unread_ims: filter_unread_ims(counts['ims'] || []),
          unread_channels: filter_unread_channels(counts['channels'] || [], muted_ids)
        }
      end

      def fetch_muted_ids(workspace)
        @options[:muted] ? [] : runner.users_api(workspace.name).muted_channels
      end

      def filter_unread_ims(ims)
        ims.select { |i| i['has_unreads'] }
      end

      def filter_unread_channels(channels, muted_ids)
        channels
          .select { |c| c['has_unreads'] || (c['mention_count'] || 0).positive? }
          .reject { |c| muted_ids.include?(c['id']) }
      end

      def output_unread_json(workspace, data)
        output_json({
                      channels: data[:unread_channels].map { |c| format_channel_json(workspace, c) },
                      dms: data[:unread_ims].map { |i| format_dm_json(workspace, i) }
                    })
      end

      def format_channel_json(workspace, channel)
        channel_hash = { id: channel['id'], mentions: channel['mention_count'] }
        channel_name = cache_store.get_channel_name(workspace.name, channel['id'])
        channel_hash[:name] = channel_name if channel_name
        channel_hash
      end

      def format_dm_json(workspace, dm_item)
        dm_hash = { id: dm_item['id'], mentions: dm_item['mention_count'] }
        user_id = dm_item['user_id'] || dm_item['user']
        if user_id
          user_name = cache_store.get_user(workspace.name, user_id)
          dm_hash[:user_name] = user_name if user_name
        end
        dm_hash
      end

      def display_unread(workspace, data)
        conversations_api = runner.conversations_api(workspace.name)
        formatter = runner.message_formatter

        display_unread_dms(workspace, data[:unread_ims], conversations_api, formatter)
        display_unread_channels(workspace, data[:unread_channels], conversations_api, formatter)
        show_threads(workspace, formatter)
      end

      def display_unread_dms(workspace, unread_ims, conversations_api, formatter)
        unread_ims.each do |im|
          mention_count = im['mention_count'] || 0
          user_name = resolve_dm_user_name(workspace, im['id'], conversations_api)
          puts
          puts output.bold("@#{user_name}") + (mention_count.positive? ? " (#{mention_count} mentions)" : '')
          puts
          show_channel_messages(workspace, im['id'], @options[:limit], conversations_api, formatter)
        end
      end

      def display_unread_channels(workspace, unreads, conversations_api, formatter)
        return puts('No unread messages') if unreads.empty?

        unreads.each { |ch| display_channel(workspace, ch, conversations_api, formatter) }
      end

      def display_channel(workspace, channel, conversations_api, formatter)
        name = cache_store.get_channel_name(workspace.name, channel['id']) || channel['id']
        puts
        puts "#{output.bold("##{name}")} (showing last #{@options[:limit]})"
        puts
        show_channel_messages(workspace, channel['id'], @options[:limit], conversations_api, formatter)
      end

      def show_threads(workspace, formatter)
        threads_response = runner.threads_api(workspace.name).get_view(limit: 20)
        return unless threads_response['ok']

        total_unreads = threads_response['total_unread_replies'] || 0
        return if total_unreads.zero?

        print_threads_header(total_unreads)
        (threads_response['threads'] || []).each { |t| display_thread(workspace, t, formatter) }
      end

      def print_threads_header(total_unreads)
        puts
        puts "#{output.bold('🧵 Threads')} (#{total_unreads} unread replies)"
        puts
      end

      def display_thread(workspace, thread, formatter)
        unread_replies = thread['unread_replies'] || []
        return if unread_replies.empty?

        print_thread_header(workspace, thread)
        print_thread_replies(workspace, thread, unread_replies, formatter)
        puts
      end

      def print_thread_header(workspace, thread)
        root_msg = thread['root_msg'] || {}
        channel_id = root_msg['channel']
        conversation_label = resolve_conversation_label(workspace, channel_id)
        root_user = extract_user_from_message(root_msg, workspace)

        puts "#{output.blue("  #{conversation_label}")} - thread by #{output.bold(root_user)}"
      end

      def print_thread_replies(workspace, thread, unread_replies, formatter)
        channel_id = (thread['root_msg'] || {})['channel']
        unread_replies.first(@options[:limit]).each do |reply|
          message = Models::Message.from_api(reply, channel_id: channel_id)
          puts "    #{formatter.format_simple(message, workspace: workspace, options: format_options)}"
        end
      end

      def show_channel_messages(workspace, channel_id, limit, api, formatter)
        messages = fetch_channel_messages(workspace, channel_id, limit, api)
        messages.each do |message|
          puts formatter.format_simple(message, workspace: workspace, options: format_options)
        end
      rescue ApiError => e
        puts output.dim("  (Could not fetch messages: #{e.message})")
      end

      def fetch_channel_messages(workspace, channel_id, limit, api)
        history = api.history(channel: channel_id, limit: limit)
        raw_messages = (history['messages'] || []).reverse
        messages = raw_messages.map { |msg| Models::Message.from_api(msg, channel_id: channel_id) }

        return messages unless @options[:reaction_timestamps]

        enricher = Services::ReactionEnricher.new(activity_api: runner.activity_api(workspace.name))
        enricher.enrich_messages(messages, channel_id)
      end

      def clear_unread(channel_name)
        target_workspaces.each do |ws|
          channel_name ? clear_single_channel(ws, channel_name) : clear_all_channels(ws)
        end
        0
      end

      def clear_single_channel(workspace, channel_name)
        channel_id = resolve_channel_id(workspace, channel_name)
        return unless unread_marker(workspace).mark_single_channel(channel_id)

        success("Marked ##{channel_name} as read on #{workspace.name}")
      end

      def clear_all_channels(workspace)
        counts = unread_marker(workspace).mark_all(options: { muted: @options[:muted] })
        success("Cleared #{counts[:channels]} channels and #{counts[:threads]} threads on #{workspace.name}")
      end

      def unread_marker(workspace)
        Services::UnreadMarker.new(
          conversations_api: runner.conversations_api(workspace.name),
          threads_api: runner.threads_api(workspace.name),
          client_api: runner.client_api(workspace.name),
          users_api: runner.users_api(workspace.name),
          on_debug: ->(msg) { debug(msg) }
        )
      end

      def resolve_channel_id(workspace, channel_name)
        return channel_name if channel_name.match?(/^[CDG][A-Z0-9]+$/)

        name = channel_name.delete_prefix('#')
        cache_store.get_channel_id(workspace.name, name) || resolve_channel(workspace, name)
      end

      def resolve_channel(workspace, name)
        api = runner.conversations_api(workspace.name)
        response = api.list
        channels = response['channels'] || []
        channel = channels.find { |c| c['name'] == name }
        channel&.dig('id') || raise(ConfigError, "Channel not found: ##{name}")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
