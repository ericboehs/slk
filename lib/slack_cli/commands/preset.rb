# frozen_string_literal: true

require_relative '../support/inline_images'
require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Manages and applies saved status presets
    # rubocop:disable Metrics/ClassLength
    class Preset < Base
      include Support::InlineImages

      def execute
        result = validate_options
        return result if result

        dispatch_action
      end

      def dispatch_action
        case positional_args
        in ['list' | 'ls'] | [] then list_presets
        in ['add'] then add_preset
        in ['edit', name] then edit_preset(name)
        in ['delete' | 'rm', name] then delete_preset(name)
        in [name, *] then apply_preset(name)
        end
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk preset <action|name> [options]')
        help.description('Manage and apply status presets.')
        add_actions_section(help)
        add_examples_section(help)
        add_options_section(help)
        help.render
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('list', 'List all presets')
          s.action('add', 'Add a new preset (interactive)')
          s.action('edit <name>', 'Edit an existing preset')
          s.action('delete <name>', 'Delete a preset')
          s.action('<name>', 'Apply a preset')
        end
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |s|
          s.example('slk preset list')
          s.example('slk preset meeting')
          s.example('slk preset add')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-w, --workspace', 'Specify workspace')
          s.option('--all', 'Apply to all workspaces')
          s.option('-q, --quiet', 'Suppress output')
        end
      end

      private

      def list_presets
        presets = preset_store.all
        return show_no_presets if presets.empty?

        puts 'Presets:'
        presets.each { |preset| display_preset(preset) }
        0
      end

      def show_no_presets
        puts 'No presets configured.'
        0
      end

      def display_preset(preset)
        puts "  #{output.bold(preset.name)}"
        display_preset_status(preset) if preset_has_status?(preset)
        display_preset_options(preset)
      end

      def preset_has_status?(preset)
        !preset.text.empty? || !preset.emoji.empty?
      end

      def display_preset_options(preset)
        puts "    Duration: #{preset.duration}" unless preset.duration == '0'
        puts "    Presence: #{preset.presence}" if preset.sets_presence?
        puts "    DND: #{preset.dnd}" if preset.sets_dnd?
      end

      def display_preset_status(preset)
        emoji_name = preset.emoji.delete_prefix(':').delete_suffix(':')
        emoji_path = find_workspace_emoji_any(emoji_name)

        if emoji_path && inline_images_supported?
          text = "    #{preset.text}"
          print_inline_image_with_text(emoji_path, text)
        else
          puts "    #{preset.emoji} #{preset.text}"
        end
      end

      def find_workspace_emoji_any(emoji_name)
        return nil if emoji_name.empty?

        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        # Search across all workspaces
        runner.all_workspaces.each do |workspace|
          workspace_dir = File.join(emoji_dir, workspace.name)
          next unless Dir.exist?(workspace_dir)

          path = Dir.glob(File.join(workspace_dir, "#{emoji_name}.*")).first
          return path if path
        end

        nil
      end

      def add_preset
        print 'Preset name: '
        name = $stdin.gets&.chomp
        return error('Name is required') if name.nil? || name.empty?

        preset = prompt_for_preset_fields(name)
        preset_store.add(preset)
        success("Preset '#{name}' created")

        0
      end

      def edit_preset(name)
        existing = preset_store.get(name)
        return error("Preset '#{name}' not found") unless existing

        puts "Editing preset '#{name}' (press Enter to keep current value)"
        preset = prompt_for_preset_fields(name, defaults: existing)
        preset_store.add(preset)
        success("Preset '#{name}' updated")

        0
      end

      def prompt_for_preset_fields(name, defaults: nil)
        Models::Preset.new(
          name: name,
          text: prompt_field('Status text', defaults&.text),
          emoji: prompt_field('Emoji (e.g., :calendar:)', defaults&.emoji),
          duration: prompt_field('Duration (e.g., 1h, 30m, or 0 for none)', defaults&.duration || '0'),
          presence: prompt_field('Presence (away/auto or blank)', defaults&.presence),
          dnd: prompt_field('DND (e.g., 1h, off, or blank)', defaults&.dnd)
        )
      end

      def prompt_field(label, default = nil)
        if default
          print "#{label} [#{default}]: "
          input = $stdin.gets&.chomp
          input.empty? ? default : input
        else
          print "#{label}: "
          $stdin.gets&.chomp || ''
        end
      end

      def delete_preset(name)
        return error("Preset '#{name}' not found") unless preset_store.exists?(name)

        preset_store.remove(name)
        success("Preset '#{name}' deleted")

        0
      end

      def apply_preset(name)
        preset = preset_store.get(name)
        return error("Preset '#{name}' not found") unless preset

        target_workspaces.each { |workspace| apply_preset_to_workspace(workspace, preset, name) }
        0
      rescue ApiError => e
        error("Failed to apply preset: #{e.message}")
        1
      end

      def apply_preset_to_workspace(workspace, preset, name)
        apply_status(workspace, preset)
        apply_presence(workspace, preset)
        apply_dnd(workspace, preset)
        success("Applied preset '#{name}' on #{workspace.name}")
      end

      def apply_status(workspace, preset)
        users_api = runner.users_api(workspace.name)
        if preset.clears_status?
          users_api.clear_status
        else
          users_api.set_status(text: preset.text, emoji: preset.emoji, duration: preset.duration_value)
        end
      end

      def apply_presence(workspace, preset)
        return unless preset.sets_presence?

        runner.users_api(workspace.name).set_presence(preset.presence)
      end

      def apply_dnd(workspace, preset)
        return unless preset.sets_dnd?

        dnd_api = runner.dnd_api(workspace.name)
        if preset.dnd == 'off'
          dnd_api.end_snooze
        else
          duration = Models::Duration.parse(preset.dnd)
          dnd_api.set_snooze(duration)
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
