# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Views and manages unread messages across workspaces
    class Unread < Base
      include Support::UserResolver

      def execute
        result = validate_options
        return result if result

        case positional_args
        in ['clear', *rest]
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

        help.section('ACTIONS') do |s|
          s.action('(none)', 'Show unread messages')
          s.action('clear', 'Mark all as read')
          s.action('clear #channel', 'Mark specific channel as read')
        end

        help.section('OPTIONS') do |s|
          s.option('-n, --limit N', 'Messages per channel (default: 10)')
          s.option('--muted', 'Include/clear muted channels')
          s.option('--no-emoji', 'Show :emoji: codes instead of unicode')
          s.option('--no-reactions', 'Hide reactions')
          s.option('--reaction-names', 'Show reactions with user names')
          s.option('--reaction-timestamps', 'Show when each person reacted')
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('--json', 'Output as JSON')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
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
        client = runner.client_api(workspace.name)
        counts = client.counts
        muted_ids = @options[:muted] ? [] : runner.users_api(workspace.name).muted_channels

        ims = counts['ims'] || []
        channels = counts['channels'] || []

        {
          unread_ims: ims.select { |i| i['has_unreads'] },
          unread_channels: channels
            .select { |c| c['has_unreads'] || (c['mention_count'] || 0).positive? }
            .reject { |c| muted_ids.include?(c['id']) }
        }
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

      def format_dm_json(workspace, im)
        dm_hash = { id: im['id'], mentions: im['mention_count'] }
        user_id = im['user_id'] || im['user']
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
        if unreads.empty?
          puts 'No unread messages' if unreads.empty?
          return
        end

        unreads.each do |channel|
          name = cache_store.get_channel_name(workspace.name, channel['id']) || channel['id']
          puts
          puts output.bold("##{name}") + " (showing last #{@options[:limit]})"
          puts
          show_channel_messages(workspace, channel['id'], @options[:limit], conversations_api, formatter)
        end
      end

      def show_threads(workspace, formatter)
        threads_api = runner.threads_api(workspace.name)
        threads_response = threads_api.get_view(limit: 20)

        return unless threads_response['ok']

        total_unreads = threads_response['total_unread_replies'] || 0
        return if total_unreads.zero?

        threads = threads_response['threads'] || []

        puts
        puts output.bold('🧵 Threads') + " (#{total_unreads} unread replies)"
        puts

        threads.each { |thread| display_thread(workspace, thread, formatter) }
      end

      def display_thread(workspace, thread, formatter)
        unread_replies = thread['unread_replies'] || []
        return if unread_replies.empty?

        root_msg = thread['root_msg'] || {}
        channel_id = root_msg['channel']
        conversation_label = resolve_conversation_label(workspace, channel_id)
        root_user = extract_user_from_message(root_msg, workspace)

        puts "#{output.blue("  #{conversation_label}")} - thread by #{output.bold(root_user)}"

        unread_replies.first(@options[:limit]).each do |reply|
          message = Models::Message.from_api(reply, channel_id: channel_id)
          puts "    #{formatter.format_simple(message, workspace: workspace, options: format_options)}"
        end

        puts
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
        target_workspaces.each do |workspace|
          marker = unread_marker(workspace)

          if channel_name
            channel_id = resolve_channel_id(workspace, channel_name)
            success("Marked ##{channel_name} as read on #{workspace.name}") if marker.mark_single_channel(channel_id)
          else
            counts = marker.mark_all(options: { muted: @options[:muted] })
            success("Cleared #{counts[:channels]} channels and #{counts[:threads]} threads on #{workspace.name}")
          end
        end

        0
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
  end
end
