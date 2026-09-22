# frozen_string_literal: true

module Slk
  module Commands
    # All indexed messages sent by the authenticated user on a date/range.
    # rubocop:disable Metrics/ClassLength
    class Sent < Base
      def execute
        result = validate_options
        return result if result

        raise UsageError, 'Use either --all or --workspace, not both.' if @options[:all] && @options[:workspace]

        query = date_query
        entries = collect_entries(query)
        emit(entries, query)
        0
      rescue ApiError => e
        error("Sent search failed: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(since: nil)
      end

      def handle_option(arg, args, remaining)
        case arg
        when '--since' then @options[:since] = option_value(arg, args)
        else super
        end
      end

      # rubocop:disable Metrics/MethodLength
      def help_text
        help = Support::HelpFormatter.new('slk sent [today|yesterday|YYYY-MM-DD] [options]')
        help.description('Show your sent messages across all workspaces, oldest first.')
        help.note('Search is indexed: very recent and deleted messages may be missing.')
        help.note('Dates use your local clock; Slack on:/after:/before: use your profile timezone.')
        help.note('Long --since ranges can be slow (search is rate-limited).')
        help.section('OPTIONS') do |s|
          s.option('--since YYYY-MM-DD', 'From this date through today (inclusive)')
          s.option('-w, --workspace NAME', 'Search one workspace instead of all')
          s.option('--all', 'Search all workspaces (default)')
          s.option('--json', 'Output counts and messages as JSON')
        end
        help.section('EXAMPLES') do |s|
          s.example('slk sent', 'Today in all workspaces')
          s.example('slk sent yesterday', 'Yesterday in all workspaces')
          s.example('slk sent 2026-09-19', 'One specific day')
          s.example('slk sent --since 2026-09-15', 'From Sep 15 through today')
        end
        help.render
      end
      # rubocop:enable Metrics/MethodLength

      private

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
