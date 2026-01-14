# frozen_string_literal: true

require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Workspaces < Base
      def execute
        result = validate_options
        return result if result

        case positional_args
        in ["list"] | []
          list_workspaces
        in ["add"]
          add_workspace
        in ["remove", name]
          remove_workspace(name)
        in ["primary"]
          show_primary
        in ["primary", name]
          set_primary(name)
        else
          error("Unknown action: #{positional_args.first}")
          1
        end
      end

      protected

      def help_text
        help = Support::HelpFormatter.new("slk workspaces <action> [name]")
        help.description("Manage Slack workspaces.")

        help.section("ACTIONS") do |s|
          s.action("list", "List configured workspaces")
          s.action("add", "Add a new workspace (interactive)")
          s.action("remove <name>", "Remove a workspace")
          s.action("primary", "Show primary workspace")
          s.action("primary <name>", "Set primary workspace")
        end

        help.section("OPTIONS") do |s|
          s.option("-q, --quiet", "Suppress output")
        end

        help.render
      end

      private

      def list_workspaces
        names = runner.workspace_names
        primary = config.primary_workspace

        if names.empty?
          puts "No workspaces configured."
          puts "Run 'slack workspaces add' to add one."
          return 0
        end

        puts "Workspaces:"
        names.each do |name|
          marker = name == primary ? output.green("*") : " "
          puts "  #{marker} #{name}"
        end

        0
      end

      def add_workspace
        print "Workspace name: "
        name = $stdin.gets&.chomp
        return error("Name is required") if name.nil? || name.empty?

        if token_store.exists?(name)
          return error("Workspace '#{name}' already exists")
        end

        print "Token (xoxb-... or xoxc-...): "
        token = $stdin.gets&.chomp
        return error("Token is required") if token.nil? || token.empty?

        cookie = nil
        if token.start_with?("xoxc-")
          print "Cookie (d=...): "
          cookie = $stdin.gets&.chomp
        end

        token_store.add(name, token, cookie)

        # Set as primary if first workspace
        if runner.workspace_names.size == 1
          config.primary_workspace = name
          success("Added workspace '#{name}' (set as primary)")
        else
          success("Added workspace '#{name}'")
        end

        0
      end

      def remove_workspace(name)
        unless token_store.exists?(name)
          return error("Workspace '#{name}' not found")
        end

        token_store.remove(name)

        # Clear primary if removing it
        if config.primary_workspace == name
          remaining = runner.workspace_names
          if remaining.any?
            config.primary_workspace = remaining.first
            success("Removed workspace '#{name}'. Primary changed to '#{remaining.first}'")
          else
            config.primary_workspace = nil
            success("Removed workspace '#{name}'")
          end
        else
          success("Removed workspace '#{name}'")
        end

        0
      end

      def show_primary
        primary = config.primary_workspace

        if primary
          puts "Primary workspace: #{primary}"
        else
          puts "No primary workspace set."
        end

        0
      end

      def set_primary(name)
        unless token_store.exists?(name)
          return error("Workspace '#{name}' not found")
        end

        config.primary_workspace = name
        success("Primary workspace set to '#{name}'")

        0
      end
    end
  end
end
