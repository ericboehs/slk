# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    class Activity < Base
      def execute
        return show_help if show_help?

        workspace = target_workspaces.first
        api = runner.activity_api(workspace.name)

        response = api.feed(limit: @options[:limit], types: activity_types)

        unless response['ok']
          error("Failed to fetch activity: #{response['error']}")
          return 1
        end

        items = response['items'] || []

        if @options[:json]
          output_json(items)
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
          filter: :all
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
        else
          remaining << arg
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
          # Unknown activity type - skip silently
        end
      end

      def display_reaction_activity(item, workspace, timestamp)
        reaction_data = item.dig('item', 'reaction')
        message_data = item.dig('item', 'message')
        return unless reaction_data && message_data

        user_id = reaction_data['user']
        username = resolve_user(workspace, user_id)
        emoji_name = reaction_data['name']
        emoji = runner.emoji_replacer.lookup_emoji(emoji_name) || ":#{emoji_name}:"
        channel_id = message_data['channel']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} #{output.bold(username)} reacted #{emoji} in #{channel}"
      end

      def display_mention_activity(item, workspace, timestamp)
        message_data = item.dig('item', 'message')
        return unless message_data

        user_id = message_data['author_user_id'] || message_data['user']
        username = resolve_user(workspace, user_id)
        channel_id = message_data['channel']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} #{output.bold(username)} mentioned you in #{channel}"
      end

      def display_thread_v2_activity(item, workspace, timestamp)
        thread_entry = item.dig('item', 'bundle_info', 'payload', 'thread_entry')
        return unless thread_entry

        channel_id = thread_entry['channel_id']
        channel = resolve_channel(workspace, channel_id)

        puts "#{output.blue(timestamp)} Thread activity in #{channel}"
      end

      def display_bot_dm_activity(item, workspace, timestamp)
        message_data = item.dig('item', 'bundle_info', 'payload', 'message')
        return unless message_data

        channel_id = message_data['channel']
        message_ts = message_data['ts']

        # Fetch the specific message using a narrow time window
        api = runner.conversations_api(workspace.name)
        # Use both oldest (exclusive) and latest (inclusive) to create a precise window
        oldest_adjusted = (message_ts.to_f - 0.000001).to_s
        latest_adjusted = (message_ts.to_f + 0.000001).to_s
        response = api.history(
          channel: channel_id,
          limit: 1,
          oldest: oldest_adjusted,
          latest: latest_adjusted
        )

        debug("Bot DM fetch: channel=#{channel_id}, ts=#{message_ts}, " \
              "ok=#{response['ok']}, messages=#{response['messages']&.length || 0}")

        if response['ok'] && response['messages']&.any?
          message = response['messages'].first

          # Get the username from the message (should be the bot name)
          username = if message['user']
                       resolve_user(workspace, message['user'])
                     elsif message['bot_id']
                       'Slackbot'
                     else
                       'Bot'
                     end

          text = message['text']
          text = '[No text]' if text.nil? || text.empty?
          # Truncate long messages
          text = "#{text[0..80]}..." if text.length > 80

          puts "#{output.blue(timestamp)} #{output.bold(username)}: #{text}"
        else
          channel = resolve_channel(workspace, channel_id)
          puts "#{output.blue(timestamp)} Bot message in #{channel}"
        end
      rescue ApiError
        # Fall back to simple display if API call fails
        channel = resolve_channel(workspace, channel_id)
        puts "#{output.blue(timestamp)} Bot message in #{channel}"
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
        rescue ApiError
          # Fall back to channel ID if API call fails
        end

        # Fall back to channel ID
        channel_id
      end

      def format_activity_time(slack_timestamp)
        time = Time.at(slack_timestamp.to_f)
        time.strftime('%b %d %-I:%M %p')  # e.g., "Jan 13 2:45 PM"
      end
    end
  end
end
