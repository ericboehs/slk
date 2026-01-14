# frozen_string_literal: true

require_relative '../support/inline_images'
require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Gets or sets user status text and emoji
    class Status < Base
      include Support::InlineImages

      def execute
        result = validate_options
        return result if result

        case positional_args
        in ['clear', *]
          clear_status
        in [text, *rest]
          set_status(text, rest)
        in []
          get_status
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(presence: nil, dnd: nil)
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-p', '--presence'
          @options[:presence] = args.shift
        when '-d', '--dnd'
          @options[:dnd] = args.shift
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk status [text] [emoji] [duration] [options]')
        help.description('Get or set your Slack status.')
        help.note('GET shows all workspaces by default. SET applies to primary only.')

        help.section('EXAMPLES') do |s|
          s.example('slk status', 'Show status (all workspaces)')
          s.example('slk status clear', 'Clear status')
          s.example('slk status "Working" :laptop:', 'Set status with emoji')
          s.example('slk status "Meeting" :calendar: 1h', 'Set status for 1 hour')
          s.example('slk status "Focus" :headphones: 2h -p away -d 2h')
        end

        help.section('OPTIONS') do |s|
          s.option('-p, --presence VALUE', 'Also set presence (away/auto/active)')
          s.option('-d, --dnd DURATION', "Also set DND (or 'off')")
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('--all', 'Set across all workspaces')
          s.option('-v, --verbose', 'Show debug information')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def get_status
        # GET defaults to all workspaces unless -w specified
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces

        workspaces.each do |workspace|
          status = runner.users_api(workspace.name).get_status

          puts output.bold(workspace.name) if workspaces.size > 1

          if status.empty?
            puts '  (no status set)'
          else
            display_status(workspace, status)
          end
        end

        0
      end

      def display_status(workspace, status)
        # Check if emoji is a custom workspace emoji with an image
        emoji_name = status.emoji.delete_prefix(':').delete_suffix(':')
        emoji_path = find_workspace_emoji(workspace.name, emoji_name)

        if emoji_path && inline_images_supported?
          # Build status text without emoji (we'll display it as image)
          parts = []
          parts << status.text unless status.text.empty?
          if (remaining = status.time_remaining)
            parts << "(#{remaining})"
          end
          text = "  #{parts.join(' ')}"

          print_inline_image_with_text(emoji_path, text)
        else
          puts "  #{status}"
        end
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
        # Parse emoji and duration from rest
        emoji = rest.find { |arg| arg.start_with?(':') && arg.end_with?(':') } || ':speech_balloon:'
        duration_str = rest.find { |arg| arg.match?(/^\d+[hms]?$/) }
        duration = duration_str ? Models::Duration.parse(duration_str) : Models::Duration.zero

        target_workspaces.each do |workspace|
          api = runner.users_api(workspace.name)
          api.set_status(text: text, emoji: emoji, duration: duration)

          success("Status set on #{workspace.name}")
          debug("  Text: #{text}")
          debug("  Emoji: #{emoji}")
          debug("  Duration: #{duration}") unless duration.zero?

          # Handle combo options
          apply_presence(workspace) if @options[:presence]
          apply_dnd(workspace) if @options[:dnd]
        end

        show_all_workspaces_hint

        0
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

      def show_all_workspaces_hint
        # Show hint if user has multiple workspaces and didn't use --all or -w
        return if @options[:all] || @options[:workspace]
        return if runner.all_workspaces.size <= 1

        info('Tip: Use --all to set across all workspaces')
      end
    end
  end
end
