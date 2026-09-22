# frozen_string_literal: true

module Slk
  module Commands
    # All indexed messages sent by the authenticated user on a date/range.
    # rubocop:disable Metrics/ClassLength
    class Sent < Base
      def execute
        result = validate_options
        return result if result

        run_sent
      rescue ApiError => e
        error("Sent search failed: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(since: nil, mine: false, before: Services::SentConversations::DEFAULT_BEFORE,
                    after_minutes: Services::SentConversations::DEFAULT_AFTER_MINUTES,
                    max: Services::SentConversations::DEFAULT_MAX)
      end

      def handle_option(arg, args, remaining)
        case arg
        when '--since' then @options[:since] = option_value(arg, args)
        when '--mine' then @options[:mine] = true
        when '--before' then @options[:before] = before_limit(arg, args)
        when '--after-minutes' then @options[:after_minutes] = nonnegative_integer(arg, args)
        when '--max' then @options[:max] = nonnegative_integer(arg, args)
        else super
        end
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def help_text
        help = Support::HelpFormatter.new('slk sent [today|yesterday|YYYY-MM-DD] [options]')
        help.description('Catch up on conversations you posted in, across all workspaces.')
        help.note('Search is indexed: very recent and deleted messages may be missing.')
        help.note('Dates/DM history bounds use your local clock; Slack search uses your profile timezone.')
        help.note('Long --since ranges can be slow (search is rate-limited; 429s retry once).')
        help.note('Conversations you only read or were mentioned in but never posted in are out of scope.')
        help.note('A future --mentions flag could seed mentioned conversations via to:me search.')
        help.note('JSON: {date, range, conversations:[{workspace, channel_id, channel_name, type,')
        help.note('thread_ts, last_speaker_is_me, dropped_messages, messages:[{ts, user,')
        help.note('user_name, text, mine, thread_ts}]}]}; --mine keeps counts/results JSON.')
        help.section('OPTIONS') do |s|
          s.option('--since YYYY-MM-DD', 'From this date through today (inclusive)')
          s.option('--mine', 'Only your messages, flat timeline with counts (previous behavior)')
          s.option('--before N', 'Channel messages before a window (default: 5, max: 200)')
          s.option('--after-minutes N', 'Channel window after each post (default: 30)')
          s.option('--max N', 'Messages per conversation (default: 200; 0 for all)')
          s.option('-w, --workspace NAME', 'Search one workspace instead of all')
          s.option('--all', 'Search all workspaces (default)')
          s.option('--json', 'Output conversations as JSON (or counts/results with --mine)')
        end
        help.section('EXAMPLES') do |s|
          s.example('slk sent', 'Today in all workspaces')
          s.example('slk sent yesterday', 'Yesterday in all workspaces')
          s.example('slk sent 2026-09-19', 'One specific day')
          s.example('slk sent --since 2026-09-15', 'From Sep 15 through today')
          s.example('slk sent --mine --json', 'Only your sent messages, flat JSON')
        end
        help.render
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      def run_sent
        raise UsageError, 'Use either --all or --workspace, not both.' if @options[:all] && @options[:workspace]

        query = date_query
        entries = collect_entries(query)
        @options[:mine] ? emit(entries, query) : emit_context(entries)
        0
      end

      def before_limit(flag, args)
        number = nonnegative_integer(flag, args)
        raise UsageError, '--before must be at most 200.' if number > 200

        number
      end

      def nonnegative_integer(flag, args)
        value = option_value(flag, args)
        number = Integer(value, exception: false)
        raise UsageError, "#{flag} expects a non-negative integer." unless number && !number.negative?

        number
      end

      def date_query
        raise UsageError, 'Use either a date or --since, not both.' if @options[:since] && positional_args.any?
        raise UsageError, 'Expected one date: today, yesterday, or YYYY-MM-DD.' if positional_args.length > 1

        @options[:since] ? range_query : day_query
      end

      def range_query
        since = parse_date(@options[:since])
        raise UsageError, '--since must not be in the future.' if since > Date.today

        "from:me after:#{since - 1} before:#{Date.today + 1}"
      end

      def day_query
        date = case positional_args.first
               when nil, 'today' then Date.today
               when 'yesterday' then Date.today - 1
               else parse_date(positional_args.first)
               end
        "from:me on:#{date}"
      end

      def parse_date(value)
        raise UsageError, "Invalid date: #{value.inspect}. Use YYYY-MM-DD." unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        Date.iso8601(value)
      rescue Date::Error
        raise UsageError, "Invalid date: #{value.inspect}. Use YYYY-MM-DD."
      end

      def collect_entries(query)
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces
        entries = workspaces.flat_map { |workspace| fetch_workspace(workspace, query) }
        entries.sort_by { |workspace, result| [result.ts.to_f, workspace.name, result.channel_id.to_s] }
      end

      def fetch_workspace(workspace, query)
        pages = Services::SearchPages.new(runner.search_api(workspace.name)).fetch(query: query, sort_dir: 'asc')
        pages[:results].map { |result| [workspace, result] }
      end

      def emit_context(entries)
        start_date, end_date = selected_dates
        conversations = Services::SentConversations.new(
          runner: runner, start_date: start_date, end_date: end_date,
          before: @options[:before], after_minutes: @options[:after_minutes], max: @options[:max]
        ).collect(entries)
        Formatters::SentFormatter.new(runner: runner, options: format_options).display(
          conversations, start_date: start_date, end_date: end_date, json: @options[:json]
        )
      end

      def selected_dates
        return [parse_date(@options[:since]), Date.today] if @options[:since]

        date = case positional_args.first
               when nil, 'today' then Date.today
               when 'yesterday' then Date.today - 1
               else parse_date(positional_args.first)
               end
        [date, date]
      end

      def emit(entries, query)
        counts = entries.group_by { |workspace, result| [workspace.name, result.channel_id] }
        if @options[:json]
          output_json(query: query, counts: json_counts(counts), results: entries.map do |workspace, result|
            result.to_h.merge(workspace: workspace.name)
          end)
        else
          display_counts(counts, entries)
        end
      end

      def json_counts(counts)
        counts.map do |(workspace, channel_id), group|
          result = group.first.last
          { workspace: workspace, channel_id: channel_id, channel_name: result.channel_name,
            channel_type: result.channel_type, count: group.size }
        end
      end

      def display_counts(counts, entries)
        if entries.empty?
          puts 'No sent messages found.'
          return
        end

        counts.each_value { |group| display_count(group) }
        puts
        entries.each do |workspace, result|
          runner.search_formatter.display_result(result, workspace, format_options.merge(workspace_label: true))
        end
      end

      def display_count(group)
        workspace, result = group.first
        channel = runner.search_formatter.channel_label(result, workspace)
        puts "[#{workspace.name}] #{channel}: #{group.size}"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
