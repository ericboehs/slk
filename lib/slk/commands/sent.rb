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
        super.merge(since: nil, mine: false, changed_since: nil, lookback: 7, context: 2,
                    before: Services::SentConversations::DEFAULT_BEFORE,
                    after_minutes: Services::SentConversations::DEFAULT_AFTER_MINUTES,
                    max: Services::SentConversations::DEFAULT_MAX)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      def handle_option(arg, args, remaining)
        case arg
        when '--since' then @options[:since] = option_value(arg, args)
        when '--changed-since' then @options[:changed_since] = option_value(arg, args)
        when '--lookback' then @options[:lookback] = positive_integer(arg, args)
        when '--context' then @options[:context] = nonnegative_integer(arg, args)
        when '--mine' then @options[:mine] = true
        when '--before' then @options[:before] = before_limit(arg, args)
        when '--after-minutes' then @options[:after_minutes] = nonnegative_integer(arg, args)
        when '--max' then @options[:max] = nonnegative_integer(arg, args)
        else super
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def help_text
        help = Support::HelpFormatter.new('slk sent [today|yesterday|YYYY-MM-DD] [options]')
        help.description('Catch up on conversations you posted in, across all workspaces.')
        help.note('Search is indexed: very recent and deleted messages may be missing.')
        help.note('Dates/DM history bounds use your local clock; Slack search uses your profile timezone.')
        help.note('Long --since ranges can be slow (search is rate-limited; 429s retry once).')
        help.note('Conversations you only read or were mentioned in but never posted in are out of scope.')
        help.note('A future --mentions flag could seed mentioned conversations via to:me search.')
        help.note('JSON: {date, range, conversations:[{workspace, channel_id, channel_name, channel_label, type,')
        help.note('thread_ts, last_speaker_is_me, dropped_messages, messages:[{ts, user,')
        help.note('user_name, text, mine, thread_ts}]}]}; --mine keeps counts/results JSON,')
        help.note('with channel_label added to counts. channel_name remains the raw Slack name.')
        help.note('JSON messages stay flat and timestamp-sorted; thread_ts links replies to their parent.')
        help.note('Text output nests expanded replies under their parent, even when sent later.')
        help.note('--changed-since is stateless: exact-ts history/replies detect new messages; search only finds')
        help.note('the watch set. Edits/reactions do not change ts and are invisible. Search index lag may')
        help.note('omit posts from the last few minutes. Conversations you never posted in remain out of scope.')
        help.note('Unread followed threads supplement the watch set when available; --lookback must include')
        help.note('the days you posted in any other threads you want to watch.')
        help.note('A wide lookback checks many thread roots and can take minutes under Slack rate limits.')
        help.note('Changed JSON adds changed_since:{iso, ts}, lookback_days, new_count, new_from_others,')
        help.note('and per-message new. Its messages stay flat and timestamp-sorted with thread_ts links.')
        help.section('OPTIONS') do |s|
          s.option('--since YYYY-MM-DD', 'From this date through today (inclusive)')
          s.option('--changed-since TIME', 'Only changed conversations (HH:MM, ISO, epoch, 90m, 2h, 1d)')
          s.option('--lookback DAYS', 'Days of sent messages to watch (default: 7; changed mode)')
          s.option('--context N', 'Earlier messages per changed conversation (default: 2)')
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
          s.example('slk sent --changed-since 15:17 --lookback 3', 'Diff watched conversations since 15:17')
        end
        help.render
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      def run_sent
        raise UsageError, 'Use either --all or --workspace, not both.' if @options[:all] && @options[:workspace]

        return run_changes if @options[:changed_since]

        query = date_query
        entries = collect_entries(query)
        @options[:mine] ? emit(entries, query) : emit_context(entries)
        0
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def run_changes
        validate_changed_options
        since = Support::CheckInTime.parse(@options[:changed_since])
        entries = collect_entries(changed_query)
        changes = Services::SentChanges.new(
          runner: runner, since: since, context: @options[:context], max: @options[:max],
          before: @options[:before], after_minutes: @options[:after_minutes]
        ).collect(entries, workspaces: selected_workspaces)
        Formatters::SentFormatter.new(runner: runner, options: format_options).display_changes(
          changes, changed_since: since, lookback_days: @options[:lookback], json: @options[:json]
        )
        0
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def validate_changed_options
        if positional_args.any? || @options[:since]
          raise UsageError, 'Use --changed-since alone, not with a date or --since.'
        end
        raise UsageError, 'Use --changed-since without --mine.' if @options[:mine]
      end

      def changed_query
        start_date = Date.today - (@options[:lookback] - 1)
        "from:me after:#{start_date - 1} before:#{Date.today + 1}"
      end

      def positive_integer(flag, args)
        number = nonnegative_integer(flag, args)
        raise UsageError, "#{flag} expects a positive integer." if number.zero?

        number
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
        entries = selected_workspaces.flat_map { |workspace| fetch_workspace(workspace, query) }
        entries.sort_by { |workspace, result| [result.ts.to_f, workspace.name, result.channel_id.to_s] }
      end

      def selected_workspaces
        @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces
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
            channel_label: destination_label(runner.workspace(workspace), result),
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
        entries.each { |workspace, result| display_entry(workspace, result) }
      end

      def display_entry(workspace, result)
        options = format_options.merge(workspace_label: true, channel_label: destination_label(workspace, result))
        runner.search_formatter.display_result(result, workspace, options)
      end

      def display_count(group)
        workspace, result = group.first
        puts "[#{workspace.name}] #{destination_label(workspace, result)}: #{group.size}"
      end

      def destination_label(workspace, result)
        runner.sent_channel_label.label(
          workspace: workspace, type: result.channel_type, name: result.channel_name,
          channel_id: result.channel_id, self_user_id: result.user_id, self_username: result.username
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
