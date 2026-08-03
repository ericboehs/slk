# frozen_string_literal: true

require_relative '../support/inline_images'
require_relative '../support/help_formatter'

module Slk
  module Commands
    # Gets or sets user status text and emoji
    # rubocop:disable Metrics/ClassLength
    class Status < Base
      include Support::InlineImages

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
        super.merge(presence: nil, dnd: nil, with_dnd: false)
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-p', '--presence'
          @options[:presence] = args.shift
        when '-d', '--dnd'
          @options[:dnd] = args.shift
        when '--with-dnd'
          @options[:with_dnd] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk status [text] [emoji] [duration] [options]')
        help.description('Get or set your Slack status.')
        help.note('GET shows all workspaces by default. SET applies to primary only.')
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
          s.example('slk status scheduled', 'List pending scheduled statuses')
          s.example('slk status unschedule CS0BMQDDGWTU', 'Cancel a scheduled status')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-p, --presence VALUE', 'Also set presence (away/auto/active)')
          s.option('-d, --dnd DURATION', "Also set DND (or 'off')")
          s.option('--with-dnd', 'When scheduling, also pause notifications while active')
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('--all', 'Set across all workspaces')
          s.option('-v, --verbose', 'Show debug information')
          s.option('-q, --quiet', 'Suppress output')
        end
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
        return error('Usage: slk status schedule "<text>" [:emoji:] <start-end>') if text.nil?

        range = extract_time_range(rest)
        return missing_range_error unless range

        starts_at, ends_at = Support::TimeRangeParser.parse(range)
        create_scheduled_status(text, extract_emoji(rest), starts_at, ends_at)
        show_all_workspaces_hint
        0
      rescue ArgumentError => e
        error(e.message)
      end

      def missing_range_error
        error('Missing time range. Example: slk status schedule "Vet Appt" :paw_prints: 1:30p-3:30p')
      end

      # The range may arrive as one token ("1:30p-3:30p") or several
      # ("2026-08-04 13:30-15:30"), so try the joined form before each token.
      def extract_time_range(rest)
        candidates = rest.reject { |arg| arg.start_with?(':') && arg.end_with?(':') }
        joined = candidates.join(' ')
        return joined if Support::TimeRangeParser.match?(joined)

        candidates.find { |arg| Support::TimeRangeParser.match?(arg) }
      end

      def create_scheduled_status(text, emoji, starts_at, ends_at)
        target_workspaces.each do |workspace|
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

        workspaces.each do |workspace|
          puts output.bold(workspace.name) if workspaces.size > 1
          print_scheduled(runner.custom_status_api(workspace.name).scheduled)
        end

        0
      end

      def print_scheduled(scheduled)
        return puts '  (none scheduled)' if scheduled.empty?

        scheduled.each { |status| puts "  #{status.id}  #{status}" }
      end

      def unschedule_status(args)
        id = args.first
        return error('Usage: slk status unschedule <id>') if id.nil?

        target_workspaces.each do |workspace|
          runner.custom_status_api(workspace.name).delete_scheduled(id)
          success("Cancelled scheduled status on #{workspace.name}")
        end

        0
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
