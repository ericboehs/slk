# frozen_string_literal: true

require_relative '../support/help_formatter'

module Slk
  module Commands
    # Searches messages across channels and DMs
    # Note: Requires user tokens (xoxc/xoxs), NOT bot tokens (xoxb)
    # rubocop:disable Metrics/ClassLength
    class Search < Base
      def execute
        result = validate_options
        return result if result

        query = positional_args.first
        return missing_query_error unless query

        search_and_display(query)
      rescue ApiError => e
        handle_api_error(e)
      rescue ArgumentError => e
        error(e.message)
        1
      end

      protected

      def default_options
        super.merge(
          limit: 20,
          page: 1,
          in_channel: nil,
          from_user: nil,
          after_date: nil,
          before_date: nil,
          on_date: nil,
          threads: false
        )
      end

      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
      def handle_option(arg, args, remaining)
        case arg
        when '-n', '--limit' then @options[:limit] = positive_integer(arg, args)
        when '--page' then @options[:page] = positive_integer(arg, args)
        when '--in' then @options[:in_channel] = require_value(arg, args)
        when '--from' then @options[:from_user] = require_value(arg, args)
        when '--after' then @options[:after_date] = require_value(arg, args)
        when '--before' then @options[:before_date] = require_value(arg, args)
        when '--on' then @options[:on_date] = require_value(arg, args)
        when '--threads' then @options[:threads] = true
        else super
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize

      def require_value(option, args)
        value = args.shift
        raise ArgumentError, "#{option} requires a value" unless value && !value.start_with?('-')

        value
      end

      def positive_integer(option, args)
        value = require_value(option, args)
        number = Integer(value, exception: false)
        raise ArgumentError, "#{option} expects a positive integer" unless number&.positive?

        number
      end

      def help_text
        help = Support::HelpFormatter.new('slk search <query> [options]')
        help.description('Search messages across channels and DMs.')
        help.note('Requires user token (xoxc/xoxs), not bot tokens.')
        add_filter_section(help)
        add_options_section(help)
        help.render
      end

      private

      def add_filter_section(help)
        help.section('FILTERS') do |s|
          s.option('--in #channel', 'Search in specific channel')
          s.option('--from @user', 'Messages from specific user')
          s.option('--after YYYY-MM-DD', 'Messages after date')
          s.option('--before YYYY-MM-DD', 'Messages before date')
          s.option('--on YYYY-MM-DD', 'Messages on specific date')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-n, --limit N', 'Results per workspace (default: 20; paginates past 100)')
          s.option('--page N', 'Starting page in each workspace')
          s.option('--threads', 'Show thread replies inline')
          s.option('--json', 'Output as JSON')
          s.option('-w, --workspace NAME', 'Specify workspace')
          s.option('--all', 'Search every workspace (results tagged by workspace)')
          s.option('-v, --verbose', 'Show debug information')
          s.option('-q, --quiet', 'Suppress output')
        end
      end

      def missing_query_error
        error('Usage: slk search <query> [options]')
        error('Example: slk search "deployment error" --in #engineering')
        1
      end

      def handle_api_error(err)
        if err.message.include?('not_allowed_token_type')
          error('Search requires a user token (xoxc/xoxs), not a bot token.')
          error('Re-run `slk config` to set up with a user token.')
        else
          error("Search failed: #{err.message}")
        end
        1
      end

      def search_and_display(query)
        raise ArgumentError, 'Use either --all or --workspace, not both' if @options[:all] && @options[:workspace]

        full_query = build_query(query)
        debug("Searching: #{full_query}")
        searches = target_workspaces.map do |workspace|
          [workspace, Services::SearchPages.new(runner.search_api(workspace.name)).fetch(
            query: full_query, limit: @options[:limit], page: @options[:page]
          )]
        end
        display_results(searches)
        0
      end

      def build_query(base_query)
        parts = [base_query]
        parts << "in:#{@options[:in_channel]}" if @options[:in_channel]
        parts << "from:#{@options[:from_user]}" if @options[:from_user]
        parts << "after:#{@options[:after_date]}" if @options[:after_date]
        parts << "before:#{@options[:before_date]}" if @options[:before_date]
        parts << "on:#{@options[:on_date]}" if @options[:on_date]
        parts.join(' ')
      end

      def display_results(searches)
        if @options[:json]
          output_json_results(searches)
        else
          display_text_results(searches)
        end
      end

      def output_json_results(searches)
        results = searches.flat_map do |workspace, data|
          data[:results].map { |result| result.to_h.merge(workspace: workspace.name) }
        end
        output_json(results: results, pagination: json_pagination(searches))
      end

      def json_pagination(searches)
        pages = searches.to_h do |workspace, data|
          [workspace.name, data[:pagination].merge('truncated' => data[:truncated] == true)]
        end
        searches.length == 1 ? pages.values.first : pages
      end

      def display_text_results(searches)
        searches.each { |workspace, data| report_search(workspace, data) }
        entries = searches.flat_map { |workspace, data| data[:results].map { |result| [result, workspace] } }
        return puts 'No results found.' if entries.empty?

        entries.each_with_index do |(result, workspace), index|
          display_single_result(result, workspace)
          puts if index < entries.length - 1
        end
      end

      def report_search(workspace, data)
        show_pagination_info(data[:pagination], workspace) if @options[:verbose]
        return unless data[:truncated]

        total = data[:pagination]['total_count']
        quantity = total ? "#{data[:results].length} of #{total}" : data[:results].length.to_s
        warn("#{workspace.name}: Showing #{quantity} matches; raise -n for more.")
      end

      def display_single_result(result, workspace)
        runner.search_formatter.display_result(result, workspace, format_options.merge(workspace_label: @options[:all]))
        show_thread_replies(result, workspace) if should_show_thread?(result)
      end

      def should_show_thread?(result)
        @options[:threads] && result.thread_ts == result.ts
      end

      def show_thread_replies(result, workspace)
        api = runner.conversations_api(workspace.name)
        replies = fetch_thread_replies(api, result.channel_id, result.ts)

        replies[1..].each { |reply| display_thread_reply(reply, workspace, result.channel_id) }
      rescue ApiError => e
        debug("Failed to fetch thread replies for #{result.ts}: #{e.message}")
      end

      def fetch_thread_replies(api, channel_id, thread_ts)
        response = api.replies(channel: channel_id, timestamp: thread_ts, limit: 100)
        response['messages'] || []
      end

      def display_thread_reply(reply_data, workspace, channel_id)
        message = Models::Message.from_api(reply_data, channel_id: channel_id)
        formatted = runner.message_formatter.format(message, workspace: workspace, options: format_options)

        lines = formatted.lines
        puts "  └ #{lines.first}"
        lines[1..].each { |line| puts "    #{line}" }
      end

      def show_pagination_info(pagination, workspace)
        total = pagination['total_count'] || 0
        page = pagination['page'] || 1
        page_count = pagination['page_count'] || 1

        debug("#{workspace.name}: Page #{page}/#{page_count} (#{total} total results)")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
