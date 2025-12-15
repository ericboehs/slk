# frozen_string_literal: true

module SlackCli
  module Commands
    class Cache < Base
      def execute
        return show_help if show_help?

        case positional_args
        in ["status" | "info"] | []
          show_status
        in ["clear", *rest]
          clear_cache(rest.first)
        in ["populate" | "refresh", *rest]
          populate_cache(rest.first)
        else
          error("Unknown action: #{positional_args.first}")
          1
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        <<~HELP
          USAGE: slack cache <action> [workspace]

          Manage user and channel cache.

          ACTIONS:
            status            Show cache status
            clear [ws]        Clear cache (all or specific workspace)
            populate [ws]     Populate user cache from API

          OPTIONS:
            -w, --workspace   Specify workspace
            -q, --quiet       Suppress output
        HELP
      end

      private

      def show_status
        target_workspaces.each do |workspace|
          if target_workspaces.size > 1
            puts output.bold(workspace.name)
          end

          user_count = cache_store.user_cache_size(workspace.name)
          channel_count = cache_store.channel_cache_size(workspace.name)

          puts "  Users cached: #{user_count}"
          puts "  Channels cached: #{channel_count}"

          if cache_store.user_cache_file_exists?(workspace.name)
            puts "  User cache: #{output.green("present")}"
          else
            puts "  User cache: #{output.yellow("not populated")}"
          end
        end

        0
      end

      def clear_cache(workspace_name)
        if workspace_name
          cache_store.clear_user_cache(workspace_name)
          cache_store.clear_channel_cache(workspace_name)
          success("Cleared cache for #{workspace_name}")
        else
          cache_store.clear_user_cache
          cache_store.clear_channel_cache
          success("Cleared all caches")
        end

        0
      end

      def populate_cache(workspace_name)
        workspaces = workspace_name ? [runner.workspace(workspace_name)] : target_workspaces

        workspaces.each do |workspace|
          puts "Populating user cache for #{workspace.name}..."

          api = runner.users_api(workspace.name)
          all_users = []
          cursor = nil

          loop do
            response = api.list(cursor: cursor)
            members = response["members"] || []
            all_users.concat(members.map { |m| Models::User.from_api(m) })

            cursor = response.dig("response_metadata", "next_cursor")
            break if cursor.nil? || cursor.empty?

            print "."
          end

          count = cache_store.populate_user_cache(workspace.name, all_users)
          puts
          success("Cached #{count} users for #{workspace.name}")
        end

        0
      end
    end
  end
end
