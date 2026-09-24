# frozen_string_literal: true

module Slk
  module Commands
    # Show who left the workspace and when, derived from users.list.
    # Examples:
    #   slk deactivations                 # 25 most recent departures
    #   slk deactivations 90d             # everyone who left in the last 90 days
    #   slk deactivations --chart         # departures per month
    #   slk deactivations --grep engineer # filter by name, handle, title, email, ID
    #   slk deactivations --tenure        # add how long each person stayed
    #   slk deactivations --csv           # spreadsheet export of every match
    # rubocop:disable Metrics/ClassLength
    class Deactivations < Base
      DEFAULT_LIMIT = 25
      CHART_MONTHS = 12
      # Measured against a live workspace: users.profile.get answers two or
      # three calls in a row, then makes you wait out a thirty second
      # Retry-After — about eight lookups a minute averaged over a long run,
      # which is what the time estimate is built on.
      LOOKUPS_PER_MINUTE = 8
      COST_WARNING_AT = 5
      SWITCHES = {
        '--chart' => :chart, '--bots' => :bots, '--tenure' => :tenure, '--csv' => :csv,
        '--refresh' => :refresh, '--no-cache' => :refresh
      }.freeze

      def execute
        result = validate_options
        return result if result

        run
      rescue Services::StartDateLookup::MissingFieldError => e
        error(e.message)
        1
      rescue ApiError => e
        error("API error: #{e.message}")
        1
      end

      protected

      def handle_option(arg, args, _remaining)
        return switch_on(SWITCHES[arg]) if SWITCHES.key?(arg)

        case arg
        when '-n', '--limit' then @options[:limit] = parse_limit(arg, option_value(arg, args))
        when '--since' then @options[:since] = option_value(arg, args)
        when '--grep' then @options[:grep] = option_value(arg, args)
        else return super
        end
        true
      end

      def switch_on(key)
        @options[key] = true
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
          s.option('--tenure', 'Add how long each person stayed (slow: one lookup per person)')
          s.option('--grep PATTERN', 'Filter by name, handle, title, email, or user ID')
          s.option('--bots', 'Include deactivated bots and app users')
          add_output_options(s)
        end
      end

      def add_output_options(section)
        section.option('--refresh', 'Re-fetch the roster instead of using the cache')
        section.option('--csv', 'CSV of every match, for a spreadsheet')
        section.option('--json', 'Raw JSON output')
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |s|
          s.example('slk deactivations', 'Most recent departures')
          s.example('slk deactivations 90d', 'Everyone who left in the last 90 days')
          s.example('slk deactivations --chart', 'Departures per month')
          s.example('slk deactivations --tenure', 'How long each person stayed')
          s.example('slk deactivations 1y --csv > left.csv', 'Export a year of departures')
          s.example('slk deactivations 2026-01-01 -n 0', 'All departures this year')
        end
      end

      def run
        workspace = runner.workspace(@options[:workspace])
        validate_combination
        @since_label = since_spec
        @since = parse_since(@since_label)
        report = scan(workspace)
        records = collect_records(report)

        emit(workspace, report, records)
        0
      end

      # --csv and --json export every match; the terminal list is the only
      # view that pages, so it is the only one -n applies to. (--chart spans
      # its whole window too, for the same reason.)
      def emit(workspace, report, records)
        return render_csv(workspace, records) if @options[:csv]
        return render_json(workspace, report, records) if @options[:json]

        render(workspace, report, records)
      end

      # One window, or none. A second date is a different question, and
      # answering the first one silently is how you misread the answer.
      def since_spec
        extra = positional_args[1..]
        raise UsageError, "Unexpected argument: #{extra.first}. Only one time window is accepted." if extra&.any?

        @options[:since] || positional_args.first
      end

      # A histogram counts departures per month; it has no row to hang a
      # tenure on. Refusing beats quietly ignoring the flag someone paid
      # attention to type.
      # Two ways of asking for the same rows is one too many, and picking a
      # winner silently means the other flag looks broken.
      def validate_combination
        raise UsageError, '--tenure has nothing to add to --chart; drop one of them.' if
          @options[:tenure] && @options[:chart]
        raise UsageError, '--csv and --json are two different exports; pick one.' if
          @options[:csv] && @options[:json]
      end

      def collect_records(report)
        records = filter(report.records)
        @options[:chart] && @since.nil? ? last_year(records) : records
      end

      def render_json(workspace, report, records)
        output_json(json_payload(workspace, report, records, tenures(workspace, records)))
        0
      end

      def render_csv(workspace, records)
        Formatters::DeactivationCsv.new(
          output: output, tenures: @options[:tenure] ? tenures(workspace, records) : nil
        ).render(records)
        0
      end

      # Start dates cost one rate-limited call each, so they are only ever
      # fetched for rows that will actually be shown. The caller has already
      # applied -n (or deliberately not, for an export); this memo assumes one
      # record set per run, which is what a single command does.
      def tenures(workspace, records)
        return {} unless @options[:tenure]

        @tenures ||= resolve_tenures(workspace, records)
      end

      def resolve_tenures(workspace, records)
        lookup = start_date_lookup(workspace)
        announce_cost(lookup, records)
        dates = begin
          lookup.fetch(records.map(&:user_id))
        ensure
          # Even when the lookup raises: otherwise the error message arrives
          # glued to a half-drawn "start dates: 12/40".
          output.clear_progress
        end
        report_cache_error(lookup)
        records.to_h { |r| [r.user_id, Models::Tenure.build(dates[r.user_id], r.deactivated_time)] }
      end

      # The answers still arrived; they just will not be there next time.
      def report_cache_error(lookup)
        return unless lookup.cache_error

        warn("Could not save the start date cache (#{lookup.cache_error}). " \
             'These lookups will have to be repeated next run.')
      end

      def start_date_lookup(workspace)
        Services::StartDateLookup.new(
          users_api: runner.users_api(workspace.name),
          field: start_date_field(workspace),
          workspace_name: workspace.name,
          cache_store: cache_store,
          on_progress: ->(done, total) { output.progress("start dates: #{done}/#{total}") }
        )
      end

      def start_date_field(workspace)
        Services::StartDateField.new(
          team_api: runner.team_api(workspace.name),
          workspace_name: workspace.name,
          cache_store: cache_store,
          on_debug: ->(msg) { output.debug(msg) }
        )
      end

      # Better to say how long this will take than to let someone wonder
      # whether the terminal has hung.
      def announce_cost(lookup, records)
        pending = lookup.uncached_count(records.map(&:user_id))
        return if pending < COST_WARNING_AT

        minutes = [(pending.to_f / LOOKUPS_PER_MINUTE).round, 1].max
        warn("Looking up #{pending} start dates, one profile call each. Slack rate-limits these " \
             "to about #{LOOKUPS_PER_MINUTE} a minute, so this will take roughly #{minutes} " \
             "minute#{'s' if minutes > 1}. Interrupting is safe: each answer is cached as it arrives.")
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
        render_account_breakdown(formatter, report)
        render_body(formatter, workspace, records)
        footer = footer(report, records)
        return if footer.empty?

        puts
        formatter.note(footer)
      end

      # Even an empty result keeps its footer: "nobody matched" is worth much
      # less without how old the roster behind it is.
      def render_body(formatter, workspace, records)
        return info('No deactivations match.') if records.empty?

        puts
        return formatter.chart(records, **chart_bounds) if @options[:chart]

        render_list(formatter, workspace, records)
      end

      def render_list(formatter, workspace, records)
        limit = @options[:limit] || DEFAULT_LIMIT
        shown = limit.positive? ? records.first(limit) : records
        formatter.list(shown, tenures: tenures(workspace, shown))
        return unless shown.size < records.size

        puts
        formatter.note("Showing #{shown.size} of #{records.size} — use -n 0 to see them all.")
      end

      def summary_line(workspace, report, records)
        "#{workspace.name}: #{records.size} #{scope_phrase} " \
          "(#{count_label(report.active_count, 'active account')})"
      end

      # Keep each guest type visible without overflowing a narrow terminal.
      # rubocop:disable Metrics/MethodLength
      def render_account_breakdown(formatter, report)
        line = '  '
        account_parts(report).each do |part|
          combined = line == '  ' ? "#{line}#{part}" : "#{line} · #{part}"
          if @options[:width] && combined.length > @options[:width] && line != '  '
            formatter.note(line)
            line = "  #{part}"
          else
            line = combined
          end
        end
        formatter.note(line)
      end
      # rubocop:enable Metrics/MethodLength

      def account_parts(report)
        [
          count_label(report.full_member_count, 'full member'),
          count_label(report.multi_channel_guest_count, 'multi-channel guest'),
          count_label(report.single_channel_guest_count, 'single-channel guest')
        ]
      end

      def count_label(count, singular)
        "#{count} #{singular}#{'s' unless count == 1}"
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

      def json_payload(workspace, report, records, tenures = {})
        {
          workspace: workspace.name,
          fetched_at: report.fetched_at,
          **active_counts_json(report),
          accounts_ever: report.human_count,
          total_deactivated: total_deactivated(report),
          includes_bots: @options[:bots] ? true : false,
          matched: records.size,
          deactivations: records.map { |r| json_entry(r, tenures) }
        }
      end

      def active_counts_json(report)
        {
          active_members: report.active_count,
          active_full_members: report.full_member_count,
          active_multi_channel_guests: report.multi_channel_guest_count,
          active_single_channel_guests: report.single_channel_guest_count
        }
      end

      # started_on and tenure_months appear only when they were asked for:
      # a null that means "not looked up" is indistinguishable from one that
      # means "nobody filled it in".
      def json_entry(record, tenures)
        entry = record.to_h.merge(deactivated_on: record.date)
        return entry unless @options[:tenure]

        tenure = tenures[record.user_id]
        entry.merge(started_on: tenure&.started, tenure_months: tenure&.months)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
