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
          'thread_broadcast'
        else
          'message_reaction,at_user,at_user_group'
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
        when 'at_user'
          display_mention_activity(item, workspace, timestamp)
        when 'thread_message'
          display_thread_activity(item, workspace, timestamp)
        else
          # Unknown activity type - skip
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
        channel = message_data['channel']

        puts "#{output.blue(timestamp)} #{output.bold(username)} reacted #{emoji} in #{channel}"
      end

      def display_mention_activity(item, workspace, timestamp)
        message_data = item.dig('item', 'message')
        return unless message_data

        user_id = message_data['author_user_id'] || message_data['user']
        username = resolve_user(workspace, user_id)
        channel = message_data['channel']

        puts "#{output.blue(timestamp)} #{output.bold(username)} mentioned you in #{channel}"
      end

      def display_thread_activity(item, workspace, timestamp)
        message_data = item.dig('item', 'message')
        return unless message_data

        user_id = message_data['user']
        username = resolve_user(workspace, user_id)
        channel = message_data['channel']

        puts "#{output.blue(timestamp)} #{output.bold(username)} replied in thread in #{channel}"
      end

      def resolve_user(workspace, user_id)
        # Try cache first
        cached = cache_store.get_user(workspace.name, user_id)
        return cached if cached

        # Fall back to user ID
        user_id
      end

      def format_activity_time(slack_timestamp)
        time = Time.at(slack_timestamp.to_f)
        time.strftime('%b %d %-I:%M %p')  # e.g., "Jan 13 2:45 PM"
      end
    end
  end
end
