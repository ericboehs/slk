# frozen_string_literal: true

module SlackCli
  module Commands
    class Preset < Base
      def execute
        return show_help if show_help?

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
        <<~HELP
          USAGE: slack preset <action|name> [options]

          Manage and apply status presets.

          ACTIONS:
            list              List all presets
            add               Add a new preset (interactive)
            edit <name>       Edit an existing preset
            delete <name>     Delete a preset
            <name>            Apply a preset

          EXAMPLES:
            slack preset list
            slack preset meeting
            slack preset add

          OPTIONS:
            -w, --workspace     Specify workspace
            --all               Apply to all workspaces
            -q, --quiet         Suppress output
        HELP
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
          puts "    #{preset.emoji} #{preset.text}" unless preset.text.empty?
          puts "    Duration: #{preset.duration}" unless preset.duration == "0"
          puts "    Presence: #{preset.presence}" if preset.sets_presence?
          puts "    DND: #{preset.dnd}" if preset.sets_dnd?
        end

        0
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
