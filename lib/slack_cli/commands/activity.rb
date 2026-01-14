# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    class Activity < Base
      def execute
        result = validate_options
        return result if result

        workspace = target_workspaces.first
        api = runner.activity_api(workspace.name)

        response = api.feed(limit: @options[:limit], types: activity_types)

        unless response['ok']
          error("Failed to fetch activity: #{response['error']}")
          return 1
        end

        items = response['items'] || []

        if @options[:json]
          output_json(enrich_activity_items(items, workspace))
        else
          display_activity(items, workspace)
        end

        0
      rescue ApiError => e
        error("Failed to fetch activity: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(
          limit: 20,
          filter: :all,
          show_messages: false
        )
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-n', '--limit'
          @options[:limit] = args.shift.to_i
        when '--reactions'
          @options[:filter] = :reactions
        when '--mentions'
          @options[:filter] = :mentions
        when '--threads'
          @options[:filter] = :threads
        when '--show-messages', '-m'
          @options[:show_messages] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk activity [options]')
        help.description('Show recent activity from the activity feed.')

        help.section('OPTIONS') do |s|
          s.option('-n, --limit N', 'Number of items (default: 20, max: 50)')
          s.option('--reactions', 'Show only reaction activity')
          s.option('--mentions', 'Show only mentions')
          s.option('--threads', 'Show only thread replies')
          s.option('-m, --show-messages', 'Show the message content for each activity')
          s.option('--json', 'Output as JSON')
          s.option('-w, --workspace', 'Specify workspace')
          s.option('-v, --verbose', 'Show debug information')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def activity_types
        case @options[:filter]
        when :reactions
          'message_reaction'
        when :mentions
          'at_user,at_user_group,at_channel,at_everyone'
        when :threads
          'thread_v2'
        else
          # All activity types that the Slack web UI uses
          'thread_v2,message_reaction,bot_dm_bundle,at_user,at_user_group,at_channel,at_everyone'
        end
      end

      def display_activity(items, workspace)
        return puts 'No activity found.' if items.empty?

        items.each do |item|
          display_activity_item(item, workspace)
        end
      end

      def display_activity_item(item, workspace)
        type = item.dig('item', 'type')
        timestamp = format_activity_time(item['feed_ts'])

        case type
        when 'message_reaction'
          display_reaction_activity(item, workspace, timestamp)
        when 'at_user', 'at_user_group', 'at_channel', 'at_everyone'
          display_mention_activity(item, workspace, timestamp)
        when 'thread_v2'
          display_thread_v2_activity(item, workspace, timestamp)
        when 'bot_dm_bundle'
          display_bot_dm_activity(item, workspace, timestamp)
        else
          debug("Unknown activity type '#{type}' - skipping") if type
        end
      end

      def display_reaction_activity(item, workspace, timestamp)
        reaction_data = item.dig('item', 'reaction')
        message_data = item.dig('item', 'message')
        unless reaction_data && message_data
          debug('Could not display reaction activity - missing reaction or message data')
          return
        end

        user_id = reaction_data['user']
        username = resolve_user(workspace, user_id)
        emoji_name = reaction_data['name']
        emoji = runner.emoji_replacer.lookup_emoji(emoji_name) || ":#{emoji_name}:"
        channel_id = message_data['channel']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} #{output.bold(username)} reacted #{emoji} in #{channel}"

        return unless @options[:show_messages]

        message = fetch_message(workspace, channel_id, message_data['ts'])
        display_message_preview(message, workspace)
      end

      def display_mention_activity(item, workspace, timestamp)
        message_data = item.dig('item', 'message')
        unless message_data
          debug('Could not display mention activity - missing message data')
          return
        end

        user_id = message_data['author_user_id'] || message_data['user']
        username = resolve_user(workspace, user_id)
        channel_id = message_data['channel']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} #{output.bold(username)} mentioned you in #{channel}"

        return unless @options[:show_messages]

        message = fetch_message(workspace, channel_id, message_data['ts'])
        display_message_preview(message, workspace)
      end

      def display_thread_v2_activity(item, workspace, timestamp)
        thread_entry = item.dig('item', 'bundle_info', 'payload', 'thread_entry')
        unless thread_entry
          debug('Could not display thread activity - missing thread_entry data')
          return
        end

        channel_id = thread_entry['channel_id']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} Thread activity in #{channel}"

        return unless @options[:show_messages] && thread_entry['thread_ts']

        # Fetch the thread parent message
        message = fetch_message(workspace, channel_id, thread_entry['thread_ts'])
        display_message_preview(message, workspace)
      end

      def display_bot_dm_activity(item, workspace, timestamp)
        message_data = item.dig('item', 'bundle_info', 'payload', 'message')
        unless message_data
          debug('Could not display bot DM activity - missing message data')
          return
        end

        channel_id = message_data['channel']
        message_ts = message_data['ts']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} Bot message in #{channel}"

        # Always try to fetch and show the message content (or when --show-messages is enabled)
        return unless @options[:show_messages]

        message = fetch_message(workspace, channel_id, message_ts)
        display_message_preview(message, workspace) if message
      end

      def resolve_user(workspace, user_id)
        # Try cache first
        cached = cache_store.get_user(workspace.name, user_id)
        return cached if cached

        # Fall back to user ID
        user_id
      end

      def resolve_channel(workspace, channel_id)
        # DMs and Group DMs - don't try to resolve
        return 'DM' if channel_id.start_with?('D')
        return 'Group DM' if channel_id.start_with?('G')

        # Try cache first
        cached = cache_store.get_channel_name(workspace.name, channel_id)
        return "##{cached}" if cached

        # Try to fetch from API
        begin
          api = runner.conversations_api(workspace.name)
          response = api.info(channel: channel_id)
          if response['ok'] && response['channel']
            name = response['channel']['name']
            cache_store.set_channel(workspace.name, name, channel_id)
            return "##{name}"
          end
        rescue ApiError => e
          debug("Could not resolve channel #{channel_id}: #{e.message}")
        end

        # Fall back to channel ID
        channel_id
      end

      def fetch_message(workspace, channel_id, message_ts)
        api = runner.conversations_api(workspace.name)
        # Fetch a window of messages around the target timestamp
        # Use oldest (exclusive) and latest (inclusive) to create a window
        oldest_ts = (message_ts.to_f - 1).to_s # 1 second before
        latest_ts = (message_ts.to_f + 1).to_s # 1 second after

        response = api.history(
          channel: channel_id,
          limit: 10,
          oldest: oldest_ts,
          latest: latest_ts
        )

        return nil unless response['ok'] && response['messages']&.any?

        # Find the exact message by timestamp
        response['messages'].find { |msg| msg['ts'] == message_ts }
      rescue ApiError => e
        debug("Could not fetch message #{message_ts} from #{channel_id}: #{e.message}")
        nil
      end

      def display_message_preview(message, workspace)
        return unless message

        # Get username
        username = if message['user']
                     resolve_user(workspace, message['user'])
                   elsif message['bot_id']
                     'Bot'
                   else
                     'Unknown'
                   end

        # Get text and replace mentions
        text = message['text'] || ''
        text = '[No text]' if text.empty?
        text = runner.mention_replacer.replace(text, workspace) unless text == '[No text]'

        # Format as indented preview
        lines = text.lines
        first_line = lines.first&.strip || text
        first_line = "#{first_line[0..100]}..." if first_line.length > 100

        puts "  └─ #{username}: #{first_line}"

        # Show additional lines if any
        return unless lines.length > 1

        remaining = lines[1..2].map(&:strip).reject(&:empty?)
        remaining.each do |line|
          line = "#{line[0..100]}..." if line.length > 100
          puts "     #{line}"
        end
        puts "     [#{lines.length - 3} more lines...]" if lines.length > 3
      end

      def format_activity_time(slack_timestamp)
        time = Time.at(slack_timestamp.to_f)
        time.strftime('%b %d %-I:%M %p') # e.g., "Jan 13 2:45 PM"
      end

      # Enrich activity items with resolved user/channel names for JSON output
      def enrich_activity_items(items, workspace)
        items.map do |item|
          enriched = item.dup
          enrich_activity_item(enriched, workspace)
          enriched
        end
      end

      def enrich_activity_item(item, workspace)
        type = item.dig('item', 'type')

        case type
        when 'message_reaction'
          enrich_reaction_item(item, workspace)
        when 'at_user', 'at_user_group', 'at_channel', 'at_everyone'
          enrich_mention_item(item, workspace)
        when 'thread_v2'
          enrich_thread_item(item, workspace)
        when 'bot_dm_bundle'
          enrich_bot_dm_item(item, workspace)
        end
      end

      def enrich_reaction_item(item, workspace)
        reaction_data = item.dig('item', 'reaction')
        message_data = item.dig('item', 'message')
        unless reaction_data && message_data
          debug('Could not enrich reaction item - missing reaction or message data')
          return
        end

        user_id = reaction_data['user']
        item['item']['reaction']['user_name'] = resolve_user(workspace, user_id) if user_id

        channel_id = message_data['channel']
        item['item']['message']['channel_name'] = resolve_channel_name_only(workspace, channel_id) if channel_id
      end

      def enrich_mention_item(item, workspace)
        message_data = item.dig('item', 'message')
        unless message_data
          debug('Could not enrich mention item - missing message data')
          return
        end

        user_id = message_data['author_user_id'] || message_data['user']
        item['item']['message']['user_name'] = resolve_user(workspace, user_id) if user_id

        channel_id = message_data['channel']
        item['item']['message']['channel_name'] = resolve_channel_name_only(workspace, channel_id) if channel_id
      end

      def enrich_thread_item(item, workspace)
        thread_entry = item.dig('item', 'bundle_info', 'payload', 'thread_entry')
        unless thread_entry
          debug('Could not enrich thread item - missing thread_entry data')
          return
        end

        channel_id = thread_entry['channel_id']
        return unless channel_id

        item['item']['bundle_info']['payload']['thread_entry']['channel_name'] =
          resolve_channel_name_only(workspace, channel_id)
      end

      def enrich_bot_dm_item(item, workspace)
        message_data = item.dig('item', 'bundle_info', 'payload', 'message')
        unless message_data
          debug('Could not enrich bot DM item - missing message data')
          return
        end

        channel_id = message_data['channel']
        return unless channel_id

        item['item']['bundle_info']['payload']['message']['channel_name'] =
          resolve_channel_name_only(workspace, channel_id)
      end

      # Resolve channel to just the name (without # prefix) for JSON output
      def resolve_channel_name_only(workspace, channel_id)
        return 'DM' if channel_id.start_with?('D')
        return 'Group DM' if channel_id.start_with?('G')

        cached = cache_store.get_channel_name(workspace.name, channel_id)
        return cached if cached

        begin
          api = runner.conversations_api(workspace.name)
          response = api.info(channel: channel_id)
          if response['ok'] && response['channel']
            name = response['channel']['name']
            cache_store.set_channel(workspace.name, name, channel_id)
            return name
          end
        rescue ApiError => e
          debug("Could not resolve channel #{channel_id}: #{e.message}")
        end

        channel_id
      end
    end
  end
end
