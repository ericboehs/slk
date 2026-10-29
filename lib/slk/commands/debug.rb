# frozen_string_literal: true

module Slk
  module Commands
    # Hidden command for development spikes.
    # Dumps raw JSON from Slack endpoints to validate xoxc compatibility
    # and field shapes before building higher-level features.
    #
    # Not registered in `slk help`.
    # rubocop:disable Metrics/ClassLength
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
        in [action, target] if TARGET_ACTIONS.key?(action) then send(TARGET_ACTIONS[action], target)
        else unknown_action
        end
      end

      TARGET_ACTIONS = { 'thread' => :dump_thread, 'channel' => :dump_channel, 'huddle' => :dump_huddle }.freeze

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

      # Raw shapes behind thread subscriptions: the parent message (does it
      # carry `subscribed`/`last_read`?) and subscriptions.thread.get. Each call
      # is captured separately so one failing does not hide the other.
      def dump_thread(url)
        resolved = resolve_target(url)
        ts = resolved.thread_ts || resolved.msg_ts
        raise UsageError, 'URL must point to a specific message' unless ts

        output.puts(JSON.pretty_generate(thread_calls(resolved.workspace.name, resolved.channel_id, ts)))
        0
      end

      # Raw conversations.info: shows the flags labels key off (is_mpim,
      # properties.has_custom_mpdm_name for named group DMs, is_ext_shared).
      def dump_channel(target)
        resolved = resolve_target(target)
        info = runner.conversations_api(resolved.workspace.name).info(channel: resolved.channel_id)
        output.puts(JSON.pretty_generate(info))
        0
      end

      # Raw huddles.get for a call id (R...), or for the call a user is in
      # now. Profiles carry only the call id; this is where the channel and
      # the full participant list (Slack Connect guests too) come from.
      def dump_huddle(target)
        workspace = runner.workspace(@options[:workspace])
        call_id = huddle_call_id(workspace, target)
        output.puts(JSON.pretty_generate(Api::Huddles.new(api_client, workspace).info(call_id)))
        0
      end

      def huddle_call_id(workspace, target)
        return target if target.match?(/\AR[A-Z0-9]+\z/)

        user_id = resolve_user_id(workspace, target)
        call_id = runner.users_api(workspace.name).info(user_id).dig('user', 'profile', 'huddle_state_call_id')
        raise ApiError, "#{target} is not in a huddle" if call_id.to_s.empty?

        call_id
      end

      def resolve_target(target)
        Services::TargetResolver.new(runner: runner, cache_store: cache_store)
                                .resolve(target, default_workspace: runner.workspace(@options[:workspace]))
      end

      def thread_calls(workspace_name, channel, thread_ts)
        {
          'conversations.replies' => capture do
            runner.conversations_api(workspace_name).replies(channel: channel, timestamp: thread_ts, limit: 1)
          end,
          'subscriptions.thread.get' => capture do
            runner.threads_api(workspace_name).get(channel: channel, thread_ts: thread_ts)
          end
        }
      end

      def capture
        yield
      rescue ApiError => e
        { 'ok' => false, 'error' => e.message }
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
        error('Valid actions: profile [user], team, schema, thread <url>, channel <id|url>, huddle <call|user>')
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
            thread <url>     Dump thread parent + subscriptions.thread.get
            channel <id|url> Dump conversations.info (also #name)
            huddle <call|user> Dump huddles.get for a call id (R...) or a user's current call

          USER
            (none) | me      Self
            @handle | name   Resolved via user cache
            Uxxx             Raw user ID
        HELP
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
