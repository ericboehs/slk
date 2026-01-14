# frozen_string_literal: true

require_relative "../support/inline_images"
require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Preset < Base
      include Support::InlineImages
      def execute
        result = validate_options
        return result if result

        case positional_args
        in ["list" | "ls"] | []
          list_presets
        in ["add"]
          add_preset
        in ["edit", name]
          edit_preset(name)
        in ["delete" | "rm", name]
          delete_preset(name)
        in [name, *]
          apply_preset(name)
        end
      end

      protected

      def help_text
        help = Support::HelpFormatter.new("slk preset <action|name> [options]")
        help.description("Manage and apply status presets.")

        help.section("ACTIONS") do |s|
          s.action("list", "List all presets")
          s.action("add", "Add a new preset (interactive)")
          s.action("edit <name>", "Edit an existing preset")
          s.action("delete <name>", "Delete a preset")
          s.action("<name>", "Apply a preset")
        end

        help.section("EXAMPLES") do |s|
          s.example("slk preset list")
          s.example("slk preset meeting")
          s.example("slk preset add")
        end

        help.section("OPTIONS") do |s|
          s.option("-w, --workspace", "Specify workspace")
          s.option("--all", "Apply to all workspaces")
          s.option("-q, --quiet", "Suppress output")
        end

        help.render
      end

      private

      def list_presets
        presets = preset_store.all

        if presets.empty?
          puts "No presets configured."
          return 0
        end

        puts "Presets:"
        presets.each do |preset|
          puts "  #{output.bold(preset.name)}"
          display_preset_status(preset) unless preset.text.empty? && preset.emoji.empty?
          puts "    Duration: #{preset.duration}" unless preset.duration == "0"
          puts "    Presence: #{preset.presence}" if preset.sets_presence?
          puts "    DND: #{preset.dnd}" if preset.sets_dnd?
        end

        0
      end

      def display_preset_status(preset)
        emoji_name = preset.emoji.delete_prefix(":").delete_suffix(":")
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
        print "Preset name: "
        name = $stdin.gets&.chomp
        return error("Name is required") if name.nil? || name.empty?

        print "Status text: "
        text = $stdin.gets&.chomp || ""

        print "Emoji (e.g., :calendar:): "
        emoji = $stdin.gets&.chomp || ""

        print "Duration (e.g., 1h, 30m, or 0 for none): "
        duration = $stdin.gets&.chomp || "0"

        print "Presence (away/auto or blank): "
        presence = $stdin.gets&.chomp || ""

        print "DND (e.g., 1h, off, or blank): "
        dnd = $stdin.gets&.chomp || ""

        preset = Models::Preset.new(
          name: name,
          text: text,
          emoji: emoji,
          duration: duration,
          presence: presence,
          dnd: dnd
        )

        preset_store.add(preset)
        success("Preset '#{name}' created")

        0
      end

      def edit_preset(name)
        preset = preset_store.get(name)
        return error("Preset '#{name}' not found") unless preset

        puts "Editing preset '#{name}' (press Enter to keep current value)"

        print "Status text [#{preset.text}]: "
        text = $stdin.gets&.chomp
        text = preset.text if text.empty?

        print "Emoji [#{preset.emoji}]: "
        emoji = $stdin.gets&.chomp
        emoji = preset.emoji if emoji.empty?

        print "Duration [#{preset.duration}]: "
        duration = $stdin.gets&.chomp
        duration = preset.duration if duration.empty?

        print "Presence [#{preset.presence}]: "
        presence = $stdin.gets&.chomp
        presence = preset.presence if presence.empty?

        print "DND [#{preset.dnd}]: "
        dnd = $stdin.gets&.chomp
        dnd = preset.dnd if dnd.empty?

        updated = Models::Preset.new(
          name: name,
          text: text,
          emoji: emoji,
          duration: duration,
          presence: presence,
          dnd: dnd
        )

        preset_store.add(updated)
        success("Preset '#{name}' updated")

        0
      end

      def delete_preset(name)
        unless preset_store.exists?(name)
          return error("Preset '#{name}' not found")
        end

        preset_store.remove(name)
        success("Preset '#{name}' deleted")

        0
      end

      def apply_preset(name)
        preset = preset_store.get(name)
        return error("Preset '#{name}' not found") unless preset

        target_workspaces.each do |workspace|
          # Set status
          unless preset.clears_status?
            duration = preset.duration_value
            runner.users_api(workspace.name).set_status(
              text: preset.text,
              emoji: preset.emoji,
              duration: duration
            )
          else
            runner.users_api(workspace.name).clear_status
          end

          # Set presence
          if preset.sets_presence?
            runner.users_api(workspace.name).set_presence(preset.presence)
          end

          # Set DND
          if preset.sets_dnd?
            dnd_api = runner.dnd_api(workspace.name)
            if preset.dnd == "off"
              dnd_api.end_snooze
            else
              duration = Models::Duration.parse(preset.dnd)
              dnd_api.set_snooze(duration)
            end
          end

          success("Applied preset '#{name}' on #{workspace.name}")
        end

        0
      rescue ApiError => e
        error("Failed to apply preset: #{e.message}")
        1
      end
    end
  end
end
