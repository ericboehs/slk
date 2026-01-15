# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Manages user and channel name cache
    # rubocop:disable Metrics/ClassLength
    class Cache < Base
      def execute
        result = validate_options
        return result if result

        dispatch_action
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      private

      def dispatch_action
        case positional_args
        in ['status' | 'info'] | [] then show_status
        in ['clear', *rest] then clear_cache(rest.first)
        in ['populate' | 'refresh', *rest] then populate_cache(rest.first)
        else unknown_action
        end
      end

      def unknown_action
        error("Unknown action: #{positional_args.first}")
        1
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk cache <action> [workspace]')
        help.description('Manage user and channel cache.')
        add_actions_section(help)
        add_options_section(help)
        help.render
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('status', 'Show cache status')
          s.action('clear [ws]', 'Clear cache (all or specific workspace)')
          s.action('populate [ws]', 'Populate user cache from API')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-w, --workspace', 'Specify workspace')
          s.option('-q, --quiet', 'Suppress output')
        end
      end

      private

      def show_status
        target_workspaces.each { |workspace| display_workspace_status(workspace) }
        0
      end

      def display_workspace_status(workspace)
        puts output.bold(workspace.name) if target_workspaces.size > 1
        display_cache_counts(workspace)
        display_cache_file_status(workspace)
      end

      def display_cache_counts(workspace)
        user_count = cache_store.user_cache_size(workspace.name)
        channel_count = cache_store.channel_cache_size(workspace.name)
        puts "  Users cached: #{user_count}"
        puts "  Channels cached: #{channel_count}"
      end

      def display_cache_file_status(workspace)
        if cache_store.user_cache_file_exists?(workspace.name)
          puts "  User cache: #{output.green('present')}"
        else
          puts "  User cache: #{output.yellow('not populated')}"
        end
      end

      def clear_cache(workspace_name)
        if workspace_name
          cache_store.clear_user_cache(workspace_name)
          cache_store.clear_channel_cache(workspace_name)
          success("Cleared cache for #{workspace_name}")
        else
          cache_store.clear_user_cache
          cache_store.clear_channel_cache
          success('Cleared all caches')
        end

        0
      end

      def populate_cache(workspace_name)
        workspaces = workspace_name ? [runner.workspace(workspace_name)] : target_workspaces
        workspaces.each { |workspace| populate_workspace_cache(workspace) }
        0
      end

      def populate_workspace_cache(workspace)
        puts "Populating user cache for #{workspace.name}..."
        all_users = fetch_all_users(workspace)
        count = cache_store.populate_user_cache(workspace.name, all_users)
        puts
        success("Cached #{count} users for #{workspace.name}")
      end

      def fetch_all_users(workspace)
        api = runner.users_api(workspace.name)
        all_users = []
        cursor = nil

        loop do
          response, cursor = fetch_users_page(api, cursor)
          all_users.concat(response)
          break if cursor.nil? || cursor.empty?

          print '.'
        end

        all_users
      end

      def fetch_users_page(api, cursor)
        response = api.list(cursor: cursor)
        users = (response['members'] || []).map { |m| Models::User.from_api(m) }
        [users, response.dig('response_metadata', 'next_cursor')]
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
