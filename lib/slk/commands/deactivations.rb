# frozen_string_literal: true

module Slk
  module Commands
    # Show who left the workspace and when, derived from users.list.
    # Examples:
    #   slk deactivations                 # 25 most recent departures
    #   slk deactivations 90d             # everyone who left in the last 90 days
    #   slk deactivations --chart         # departures per month
    #   slk deactivations --grep engineer # filter by name, handle, title, email, ID
    # rubocop:disable Metrics/ClassLength
    class Deactivations < Base
      DEFAULT_LIMIT = 25
      CHART_MONTHS = 12

      def execute
        result = validate_options
        return result if result

        run
      rescue ApiError => e
        error("API error: #{e.message}")
        1
      end

      protected

      def handle_option(arg, args, _remaining)
        case arg
        when '-n', '--limit' then @options[:limit] = parse_limit(arg, option_value(arg, args))
        when '--since' then @options[:since] = option_value(arg, args)
        when '--chart' then @options[:chart] = true
        when '--bots' then @options[:bots] = true
        when '--grep' then @options[:grep] = option_value(arg, args)
        when '--refresh', '--no-cache' then @options[:refresh] = true
        else return super
        end
        true
      end

      def help_text
        help = Support::HelpFormatter.new('slk deactivations [since] [options]')
        help.description('Show deactivated accounts — who left the workspace, and when.')
        help.note("Dates come from each account's `updated` field, which for a deactivated")
        help.note('account is the deactivation itself unless an admin edited the profile after.')
        add_options_section(help)
        add_examples_section(help)
        help.render
      end

      private

      # Base defaults to 72 columns for prose wrapping; this is a table, so use
      # the whole terminal and let long titles keep their tail. A tty that
      # refuses to report its size (some Windows consoles, some CI shims) is
      # not a reason to fail before the command has even parsed its arguments.
      def default_width
        return 100 unless $stdout.tty?

        IO.console&.winsize&.last || 100
      rescue Errno::ENOTTY, Errno::EINVAL, Errno::ENODEV, IOError, NotImplementedError
        100
      end

      # `-n foo` used to reach to_i, become 0, and quietly mean "no limit" —
      # the opposite of asking for fewer rows.
      def parse_limit(flag, value)
        limit = Integer(value, exception: false)
        return limit if limit && !limit.negative?

        raise UsageError, "#{flag} expects a non-negative integer (got #{value.inspect})."
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-n, --limit N', "Rows to show (default #{DEFAULT_LIMIT}, 0 for all)")
          s.option('--since SPEC', 'Only departures since 7d, 4w, 6m, or YYYY-MM-DD')
          s.option('--chart', 'Histogram of departures per month')
          s.option('--grep PATTERN', 'Filter by name, handle, title, email, or user ID')
          s.option('--bots', 'Include deactivated bots and app users')
          s.option('--refresh', 'Re-fetch the roster instead of using the cache')
          s.option('--json', 'Raw JSON output')
        end
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |s|
          s.example('slk deactivations', 'Most recent departures')
          s.example('slk deactivations 90d', 'Everyone who left in the last 90 days')
          s.example('slk deactivations --chart', 'Departures per month')
          s.example('slk deactivations 2026-01-01 -n 0', 'All departures this year')
        end
      end

      def run
        workspace = runner.workspace(@options[:workspace])
        @since_label = since_spec
        @since = parse_since(@since_label)
        report = scan(workspace)
        records = collect_records(report)

        return render_json(workspace, report, records) if @options[:json]

        render(workspace, report, records)
        0
      end

      # One window, or none. A second date is a different question, and
      # answering the first one silently is how you misread the answer.
      def since_spec
        extra = positional_args[1..]
        raise UsageError, "Unexpected argument: #{extra.first}. Only one time window is accepted." if extra&.any?

        @options[:since] || positional_args.first
      end

      def collect_records(report)
        records = filter(report.records)
        @options[:chart] && @since.nil? ? last_year(records) : records
      end

      def render_json(workspace, report, records)
        output_json(json_payload(workspace, report, records))
        0
      end

      def scan(workspace)
        Services::DeactivationScanner.new(
          users_api: runner.users_api(workspace.name),
          workspace_name: workspace.name,
          cache_store: cache_store,
          on_debug: ->(msg) { output.debug(msg) }
        ).scan(refresh: @options[:refresh])
      end

      # Filters compose: --bots, --since, --grep all narrow the same list.
      # Records Slack never dated cannot answer a question about a window, so
      # they drop out of one — but they are counted, not silently discarded.
      def filter(records)
        records = records.reject(&:bot) unless @options[:bots]
        pattern = grep_pattern
        records = records.select { |r| r.matches?(pattern) } if pattern
        @undated = records.count { |r| r.deactivated_at.nil? }
        reject_before(records, @since)
      end

      def reject_before(records, cutoff)
        return records unless cutoff

        records.select { |r| r.deactivated_at && r.deactivated_at >= cutoff }
      end

      # An all-time histogram of a decade-old workspace is mostly scrollback.
      # Counting in months rather than in 31-day steps keeps the window exactly
      # as long as the label claims.
      def last_year(records)
        reject_before(records, last_year_cutoff)
      end

      def last_year_cutoff
        now = Time.now
        index = (now.year * 12) + (now.month - 1) - (CHART_MONTHS - 1)
        Time.new(index / 12, (index % 12) + 1, 1).to_i
      end

      # The chart spans the window that was asked for, not merely the months
      # that happen to contain a departure: a quiet opening month is the
      # answer to "how bad is it lately", and dropping it flatters the trend.
      def chart_bounds
        {
          from: Time.at(@since || last_year_cutoff).strftime('%Y-%m'),
          to: Time.now.strftime('%Y-%m')
        }
      end

      def parse_since(spec)
        return nil unless spec

        Support::DateParser.parse(spec)
      rescue ArgumentError => e
        raise UsageError, e.message
      end

      def grep_pattern
        return nil unless @options[:grep]

        Regexp.new(@options[:grep], Regexp::IGNORECASE)
      rescue RegexpError => e
        raise UsageError, "Invalid --grep pattern: #{e.message}"
      end

      def render(workspace, report, records)
        formatter = Formatters::DeactivationFormatter.new(output: output, width: @options[:width])
        formatter.summary(summary_line(workspace, report, records))
        render_body(formatter, records)
        footer = footer(report, records)
        return if footer.empty?

        puts
        formatter.note(footer)
      end

      # Even an empty result keeps its footer: "nobody matched" is worth much
      # less without how old the roster behind it is.
      def render_body(formatter, records)
        return info('No deactivations match.') if records.empty?

        puts
        @options[:chart] ? formatter.chart(records, **chart_bounds) : render_list(formatter, records)
      end

      def render_list(formatter, records)
        limit = @options[:limit] || DEFAULT_LIMIT
        shown = limit.positive? ? records.first(limit) : records
        formatter.list(shown)
        return unless shown.size < records.size

        puts
        formatter.note("Showing #{shown.size} of #{records.size} — use -n 0 to see them all.")
      end

      def summary_line(workspace, report, records)
        "#{workspace.name}: #{records.size} #{scope_phrase} " \
          "(#{report.active_count} active members)"
      end

      def scope_phrase
        return "deactivated since #{@since_label}" if @since_label

        @options[:chart] ? "deactivated in the last #{CHART_MONTHS} months" : 'deactivated accounts'
      end

      def footer(report, records)
        total = total_deactivated(report)
        age = cache_age(report)
        parts = []
        parts << "#{total} deactivated in all (of #{report.human_count} accounts ever created)" if records.size < total
        parts << undated_note if undated_note
        parts << "roster cached #{age} ago; --refresh to update" if age
        parts.join(' · ')
      end

      # Only worth saying when a window was applied: without one nothing was
      # dropped for want of a date.
      def undated_note
        return nil unless windowed? && @undated.to_i.positive?

        "#{@undated} with no recorded date omitted"
      end

      def windowed?
        !@since.nil? || @options[:chart]
      end

      def total_deactivated(report)
        return report.deactivated_count if @options[:bots]

        report.records.count { |r| !r.bot }
      end

      def cache_age(report)
        return nil unless report.fetched_at

        seconds = Time.now.to_i - report.fetched_at
        return nil if seconds < 60

        Models::Duration.new(seconds: seconds).to_s
      end

      def json_payload(workspace, report, records)
        {
          workspace: workspace.name,
          fetched_at: report.fetched_at,
          active_members: report.active_count,
          accounts_ever: report.human_count,
          total_deactivated: total_deactivated(report),
          includes_bots: @options[:bots] ? true : false,
          matched: records.size,
          deactivations: records.map { |r| r.to_h.merge(deactivated_on: r.date) }
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
