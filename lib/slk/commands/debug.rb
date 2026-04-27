# frozen_string_literal: true

module Slk
  module Commands
    # Hidden command for development spikes.
    # Dumps raw JSON from Slack endpoints to validate xoxc compatibility
    # and field shapes before building higher-level features.
    #
    # Not registered in `slk help`.
    class Debug < Base
      def execute
        result = validate_options
        return result if result

        dispatch_action
      rescue ApiError => e
        error("API error: #{e.message}")
        1
      end

      def dispatch_action
        case positional_args
        in ['profile', user] then dump_profile(user)
        in ['profile'] then dump_profile(nil)
        in ['team'] then dump_team
        in ['schema'] then dump_schema
        else unknown_action
        end
      end

      private

      def dump_profile(user_input)
        workspace = runner.workspace(@options[:workspace])
        user_id = resolve_user_id(workspace, user_input)
        users_api = runner.users_api(workspace.name)
        out = {
          'users.profile.get' => users_api.profile_for(user_id),
          'users.info' => users_api.info(user_id),
          'team.profile.get' => runner.team_api(workspace.name).profile_schema
        }
        output.puts(JSON.pretty_generate(out))
        0
      end

      def dump_team
        workspace = runner.workspace(@options[:workspace])
        output.puts(JSON.pretty_generate(runner.team_api(workspace.name).info))
        0
      end

      def dump_schema
        workspace = runner.workspace(@options[:workspace])
        output.puts(JSON.pretty_generate(runner.team_api(workspace.name).profile_schema))
        0
      end

      def resolve_user_id(workspace, user_input)
        return self_user_id(workspace) if user_input.nil? || user_input == 'me'
        return user_input if user_input.match?(/\A[UW][A-Z0-9]+\z/)

        id = lookup_for(workspace).find_id_by_name(user_input.delete_prefix('@'))
        raise ApiError, "Could not resolve user: #{user_input}" unless id

        id
      end

      def lookup_for(workspace)
        Services::UserLookup.new(
          cache_store: cache_store,
          workspace: workspace,
          api_client: api_client,
          on_debug: ->(msg) { output.debug(msg) }
        )
      end

      def self_user_id(workspace)
        client = Api::Client.new(api_client, workspace)
        response = client.auth_test
        response['user_id']
      end

      def unknown_action
        error("Unknown debug action: #{positional_args.first.inspect}")
        error('Valid actions: profile [user], team, schema')
        1
      end

      protected

      def help_text
        <<~HELP
          slk debug <action> [args]

          Hidden development command — dumps raw API responses for spike validation.

          ACTIONS
            profile [user]   Dump users.profile.get + users.info + team.profile.get
            team             Dump team.info
            schema           Dump team.profile.get

          USER
            (none) | me      Self
            @handle | name   Resolved via user cache
            Uxxx             Raw user ID
        HELP
      end
    end
  end
end
