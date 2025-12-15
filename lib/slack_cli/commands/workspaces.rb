# frozen_string_literal: true

module SlackCli
  module Commands
    class Workspaces < Base
      def execute
        return show_help if show_help?

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
        <<~HELP
          USAGE: slack workspaces <action> [name]

          Manage Slack workspaces.

          ACTIONS:
            list              List configured workspaces
            add               Add a new workspace (interactive)
            remove <name>     Remove a workspace
            primary           Show primary workspace
            primary <name>    Set primary workspace

          OPTIONS:
            -q, --quiet       Suppress output
        HELP
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
