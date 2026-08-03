# frozen_string_literal: true

require_relative '../support/inline_images'
require_relative '../support/help_formatter'

module Slk
  module Commands
    # Gets or sets user status text and emoji
    # rubocop:disable Metrics/ClassLength
    class Status < Base
      include Support::InlineImages

      SCHEDULE_USAGE = 'Usage: slk status schedule "<text>" [:emoji:] <start-end> | --start WHEN [--end WHEN]'
      MISSING_RANGE = 'Missing time range. Example: slk status schedule "Vet Appt" :paw_prints: 1:30p-3:30p ' \
                      '(or --start/--end for a multi-day window).'

      def execute
        result = validate_options
        return result if result

        dispatch_action
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      def dispatch_action
        case positional_args
        in ['schedule', *rest] then schedule_status(rest)
        in ['scheduled', *] then list_scheduled
        in ['unschedule', *rest] then unschedule_status(rest)
        in ['clear', *] then clear_status
        in [text, *rest] then set_status(text, rest)
        in [] then get_status
        end
      end

      protected

      def default_options
        super.merge(presence: nil, dnd: nil, with_dnd: false, start_at: nil, end_at: nil)
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-p', '--presence' then @options[:presence] = option_value(arg, args)
        when '-d', '--dnd' then @options[:dnd] = option_value(arg, args)
        when '--with-dnd' then @options[:with_dnd] = true
        when '--start' then @options[:start_at] = option_value(arg, args)
        when '--end' then @options[:end_at] = option_value(arg, args)
        else super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk status [text] [emoji] [duration] [options]')
        help.description('Get or set your Slack status.')
        help.note('GET shows all workspaces by default. SET applies to primary only.')
        help.note('scheduled shows all workspaces; schedule applies to primary; unschedule finds the ID owner.')
        help.note('Slack allows at most 5 scheduled statuses at a time.')
        add_examples_section(help)
        add_scheduling_section(help)
        add_options_section(help)
        help.render
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |s|
          s.example('slk status', 'Show status (all workspaces)')
          s.example('slk status clear', 'Clear status')
          s.example('slk status "Working" :laptop:', 'Set status with emoji')
          s.example('slk status "Meeting" :calendar: 1h', 'Set status for 1 hour')
          s.example('slk status "Focus" :headphones: 2h -p away -d 2h')
        end
      end

      def add_scheduling_section(help)
        help.section('SCHEDULING') do |s|
          s.example('slk status schedule "Vet Appt" :paw_prints: 1:30p-3:30p', 'Schedule for later')
          s.example('slk status schedule "OOO" :palm_tree: 2026-08-04 9:00-17:00')
          s.example('slk status schedule "OOO" :palm_tree: --start "2026-08-12 8a" --end "2026-08-14 5p"',
                    'Span multiple days')
          s.example('slk status schedule "Heads down" :no_bell: --start 2p', 'No end; stays until cleared')
          s.example('slk status scheduled', 'List pending scheduled statuses')
          s.example('slk status unschedule CS0BMQDDGWTU', 'Cancel a scheduled status')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          add_general_options(s)
          add_scheduling_options(s)
        end
      end

      def add_general_options(section)
        section.option('-p, --presence VALUE', 'Also set presence (away/auto/active)')
        section.option('-d, --dnd DURATION', "Also set DND (or 'off')")
        section.option('-w, --workspace', 'Limit to specific workspace')
        section.option('--all', 'Set across all workspaces')
        section.option('-v, --verbose', 'Show debug information')
        section.option('-q, --quiet', 'Suppress output')
      end

      # These are ignored outside `schedule`, so say so rather than leaving
      # --with-dnd looking like a sibling of -d/--dnd.
      def add_scheduling_options(section)
        section.option('--with-dnd', 'Scheduling only: pause notifications while the status is active')
        section.option('--start WHEN', 'Scheduling only: window start, "[YYYY-MM-DD ]TIME"')
        section.option('--end WHEN', 'Scheduling only: window end; omit for no expiry')
      end

      private

      def get_status # rubocop:disable Naming/AccessorMethodName
        # GET defaults to all workspaces unless -w specified
        workspaces = target_workspaces_for_get

        workspaces.each do |workspace|
          status = runner.users_api(workspace.name).get_status
          print_workspace_status(workspaces, workspace, status)
        end

        0
      end

      def target_workspaces_for_get
        @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces
      end

      def print_workspace_status(workspaces, workspace, status)
        puts output.bold(workspace.name) if workspaces.size > 1

        if status.empty?
          puts '  (no status set)'
        else
          display_status(workspace, status)
        end
      end

      def display_status(workspace, status)
        emoji_path = workspace_emoji_path(workspace.name, status.emoji)

        if emoji_path && inline_images_supported?
          print_status_with_image(emoji_path, status)
        else
          puts "  #{status}"
        end
      end

      def workspace_emoji_path(workspace_name, emoji)
        emoji_name = emoji.delete_prefix(':').delete_suffix(':')
        find_workspace_emoji(workspace_name, emoji_name)
      end

      def print_status_with_image(emoji_path, status)
        parts = []
        parts << status.text unless status.text.empty?
        parts << "(#{status.time_remaining})" if status.time_remaining
        print_inline_image_with_text(emoji_path, "  #{parts.join(' ')}")
      end

      def find_workspace_emoji(workspace_name, emoji_name)
        return nil if emoji_name.empty?

        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir
        workspace_dir = File.join(emoji_dir, workspace_name)
        return nil unless Dir.exist?(workspace_dir)

        # Look for emoji file with any extension
        Dir.glob(File.join(workspace_dir, "#{emoji_name}.*")).first
      end

      def set_status(text, rest)
        emoji = extract_emoji(rest)
        duration = extract_duration(rest)

        target_workspaces.each do |workspace|
          apply_status_to_workspace(workspace, text, emoji, duration)
        end

        show_all_workspaces_hint
        0
      end

      def extract_emoji(rest)
        rest.find { |arg| arg.start_with?(':') && arg.end_with?(':') } || ':speech_balloon:'
      end

      def extract_duration(rest)
        duration_str = rest.find { |arg| arg.match?(/^\d+[hms]?$/) }
        duration_str ? Models::Duration.parse(duration_str) : Models::Duration.zero
      end

      def apply_status_to_workspace(workspace, text, emoji, duration)
        api = runner.users_api(workspace.name)
        api.set_status(text: text, emoji: emoji, duration: duration)

        log_status_set(workspace.name, text, emoji, duration)
        apply_presence(workspace) if @options[:presence]
        apply_dnd(workspace) if @options[:dnd]
      end

      def log_status_set(workspace_name, text, emoji, duration)
        success("Status set on #{workspace_name}")
        debug("  Text: #{text}")
        debug("  Emoji: #{emoji}")
        debug("  Duration: #{duration}") unless duration.zero?
      end

      def apply_presence(workspace)
        value = @options[:presence]
        value = 'auto' if value == 'active'

        api = runner.users_api(workspace.name)
        api.set_presence(value)
        success("Presence set to #{value} on #{workspace.name}")
      end

      def apply_dnd(workspace)
        value = @options[:dnd]
        dnd_api = runner.dnd_api(workspace.name)

        if value == 'off'
          dnd_api.end_snooze
          success("DND disabled on #{workspace.name}")
        else
          duration = Models::Duration.parse(value)
          dnd_api.set_snooze(duration)
          success("DND enabled for #{value} on #{workspace.name}")
        end
      end

      def clear_status
        target_workspaces.each do |workspace|
          api = runner.users_api(workspace.name)
          api.clear_status

          success("Status cleared on #{workspace.name}")
        end

        show_all_workspaces_hint

        0
      end

      def schedule_status(args)
        text, *rest = args
        return error(SCHEDULE_USAGE) if text.to_s.strip.empty?

        window = parse_schedule_window(rest)
        return 1 unless window

        result = create_scheduled_status(text, extract_emoji(rest), *window)
        show_all_workspaces_hint
        result
      end

      # Narrow on both axes: only the parsing is covered, so a Slack failure is
      # not reported as a mistyped range, and only TimeFormatError is caught, so
      # an arity or range error from this code does not surface as user error.
      def parse_schedule_window(rest)
        return flag_window(rest) if @options[:start_at] || @options[:end_at]

        range = extract_time_range(rest)
        return reject_window(MISSING_RANGE) unless range

        Support::TimeRangeParser.parse(range)
      rescue TimeFormatError => e
        error(e.message)
        nil
      end

      # --start/--end is the general form. Both times carry their own date, so
      # it reaches multi-day windows the positional range cannot express, and
      # omitting --end schedules a status that never auto-clears.
      def flag_window(rest)
        return reject_window('--end requires --start.') unless @options[:start_at]
        return reject_window('Use either a time range or --start/--end, not both.') if extract_time_range(rest)

        starts_at = Support::TimeParser.parse(@options[:start_at])
        return [starts_at, nil] unless @options[:end_at]

        [starts_at, validated_end(starts_at)]
      end

      def validated_end(starts_at)
        ends_at = Support::TimeParser.parse(@options[:end_at])
        # An explicit end is unambiguous, so there is nothing to roll forward.
        return ends_at if ends_at > starts_at

        raise TimeFormatError, "--end #{@options[:end_at]} is not after --start #{@options[:start_at]}."
      end

      # Returns nil so the caller reads it as "no window, already reported".
      def reject_window(message)
        error(message)
        nil
      end

      # The range may arrive as one token ("1:30p-3:30p") or several
      # ("2026-08-04 13:30-15:30"), so the non-emoji arguments are matched as a
      # whole. Emoji are dropped first because the pattern is \A-anchored and a
      # leading ":palm_tree:" would stop the date form from matching at all.
      #
      # Everything left has to be part of the range. Only YYYY-MM-DD dates
      # parse, so picking the range out and discarding "8/4" or "tomorrow"
      # would silently schedule the status for today.
      def extract_time_range(rest)
        candidates = rest.reject { |arg| arg.start_with?(':') && arg.end_with?(':') }
        return nil if candidates.empty?

        joined = candidates.join(' ')
        return joined if Support::TimeRangeParser.match?(joined)

        raise TimeFormatError, "Unrecognized argument: #{joined}. Use #{Support::TimeRangeParser::EXAMPLE}"
      end

      # Each workspace is an independent call, so one failure must not strand
      # the workspaces after it: the user would re-run to fix the tail and
      # double-schedule everything that already succeeded.
      def each_workspace_reporting(workspaces)
        failed = false

        workspaces.each do |workspace|
          yield workspace
        rescue ApiError => e
          failed = true
          error("#{workspace.name}: #{e.message}")
        end

        failed ? 1 : 0
      end

      def create_scheduled_status(text, emoji, starts_at, ends_at)
        each_workspace_reporting(target_workspaces) do |workspace|
          scheduled = runner.custom_status_api(workspace.name).schedule(
            text: text, emoji: emoji,
            date_scheduled: starts_at, date_expire: ends_at,
            dnd: @options[:with_dnd]
          )
          success("Scheduled on #{workspace.name}: #{scheduled}")
          debug("  ID: #{scheduled.id}")
        end
      end

      def list_scheduled
        workspaces = target_workspaces_for_get

        each_workspace_reporting(workspaces) do |workspace|
          puts output.bold(workspace.name) if workspaces.size > 1
          print_scheduled(runner.custom_status_api(workspace.name).scheduled)
        end
      end

      def print_scheduled(scheduled)
        return puts '  (none scheduled)' if scheduled.empty?

        scheduled.each { |status| puts "  #{status.id}  #{status}" }
      end

      def unschedule_status(args)
        id = args.first
        return error('Usage: slk status unschedule <id>') if id.to_s.strip.empty?

        @unchecked = []
        targets = unschedule_targets(id)
        return report_id_not_found(id) if targets.empty?

        each_workspace_reporting(targets) do |workspace|
          outcome, reason = runner.custom_status_api(workspace.name).delete_scheduled(id)
          report_cancelled(workspace, outcome, reason)
        end
      end

      # The delete succeeded either way, so both are successes — but only one
      # of them has been checked, and saying so is the difference between the
      # user moving on and the user re-cancelling something already gone.
      def report_cancelled(workspace, outcome, reason)
        return success("Cancelled scheduled status on #{workspace.name}") if outcome == :cancelled

        warn("Cancelled scheduled status on #{workspace.name}, but could not confirm it: #{reason}")
      end

      # `slk status scheduled` lists every workspace, so the obvious next step
      # is to paste an ID straight back in. Defaulting to the primary workspace
      # made that fail with a bare Slack error whenever the ID came from
      # another one, so look up the owner instead. An explicit -w/--all still
      # wins, and a lone workspace needs no lookup.
      def unschedule_targets(id)
        return target_workspaces if @options[:all] || @options[:workspace]

        workspaces = runner.all_workspaces
        return workspaces if workspaces.size <= 1

        [workspaces.find { |workspace| owns_scheduled?(workspace, id) }].compact
      end

      # "Not found" is only true of the workspaces we actually reached. Saying
      # it flatly after warning that one could not be checked contradicts the
      # warning, and pointing at `slk status scheduled` would just fail the
      # same way — it calls the same endpoint.
      def report_id_not_found(id)
        return error("No scheduled status #{id} found. Run 'slk status scheduled' to list IDs.") if @unchecked.empty?

        error("#{id} was not found, but #{@unchecked.join(', ')} could not be checked. " \
              'Retry, or name the workspace with -w to cancel it directly.')
      end

      def owns_scheduled?(workspace, id)
        runner.custom_status_api(workspace.name).scheduled.any? { |status| status.id == id }
      rescue RateLimitError
        # Every remaining check spends another call against the same limit, so
        # continuing turns one rate limit into several and still cannot answer.
        raise
      rescue ApiError => e
        # Skipping it silently would report "not found" for an ID that exists.
        warn("Could not check #{workspace.name}: #{e.message}")
        @unchecked << workspace.name
        false
      end

      def show_all_workspaces_hint
        # Show hint if user has multiple workspaces and didn't use --all or -w
        return if @options[:all] || @options[:workspace]
        return if runner.all_workspaces.size <= 1

        info('Tip: Use --all to set across all workspaces')
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
