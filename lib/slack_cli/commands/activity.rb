# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Displays recent activity feed items (reactions, mentions, threads)
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
          output_json(enricher(workspace).enrich_all(items, workspace))
        else
          formatter(workspace).display_all(items, workspace, options: display_options(workspace))
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

      def enricher(workspace)
        Services::ActivityEnricher.new(
          cache_store: cache_store,
          conversations_api: runner.conversations_api(workspace.name),
          on_debug: ->(msg) { debug(msg) }
        )
      end

      def formatter(workspace)
        Formatters::ActivityFormatter.new(
          output: output,
          enricher: enricher(workspace),
          emoji_replacer: runner.emoji_replacer,
          mention_replacer: runner.mention_replacer,
          on_debug: ->(msg) { debug(msg) }
        )
      end

      def display_options(_workspace)
        {
          show_messages: @options[:show_messages],
          fetch_message: ->(ws, channel_id, message_ts) { fetch_message(ws, channel_id, message_ts) }
        }
      end

      def fetch_message(workspace, channel_id, message_ts)
        api = runner.conversations_api(workspace.name)
        oldest_ts = (message_ts.to_f - 1).to_s
        latest_ts = (message_ts.to_f + 1).to_s

        response = api.history(channel: channel_id, limit: 10, oldest: oldest_ts, latest: latest_ts)
        return nil unless response['ok'] && response['messages']&.any?

        response['messages'].find { |msg| msg['ts'] == message_ts }
      rescue ApiError => e
        debug("Could not fetch message #{message_ts} from #{channel_id}: #{e.message}")
        nil
      end
    end
  end
end
