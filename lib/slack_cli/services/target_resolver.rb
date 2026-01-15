# frozen_string_literal: true

module SlackCli
  module Services
    # Resolves message targets (channels, DMs, URLs) to channel IDs
    class TargetResolver
      Result = Data.define(:workspace, :channel_id, :thread_ts, :msg_ts)

      def initialize(runner:, cache_store:)
        @runner = runner
        @cache = cache_store
      end

      # Resolve a target string to workspace, channel_id, and optional thread/message ts
      # @param target [String] Channel name, @user, channel ID, or Slack URL
      # @param default_workspace [Workspace] Workspace to use if not in URL
      # @return [Result] Resolved target
      def resolve(target, default_workspace:)
        url_result = resolve_url(target)
        return url_result if url_result

        resolve_non_url(target, default_workspace)
      end

      private

      def resolve_non_url(target, workspace)
        return build_result(workspace, target) if channel_id?(target)
        return resolve_channel_target(workspace, target) unless target.start_with?('@')
        return resolve_dm_target(workspace, target) if target.start_with?('@')

        raise ConfigError, "Could not resolve target: #{target}"
      end

      def channel_id?(target)
        target.match?(/^[CDG][A-Z0-9]+$/)
      end

      def resolve_channel_target(workspace, target)
        channel_id = resolve_channel(workspace, target.delete_prefix('#'))
        build_result(workspace, channel_id)
      end

      def resolve_dm_target(workspace, target)
        channel_id = resolve_dm(workspace, target.delete_prefix('@'))
        build_result(workspace, channel_id)
      end

      def build_result(workspace, channel_id, thread_ts: nil, msg_ts: nil)
        Result.new(workspace: workspace, channel_id: channel_id, thread_ts: thread_ts, msg_ts: msg_ts)
      end

      def resolve_url(target)
        url_parser = Support::SlackUrlParser.new
        return nil unless url_parser.slack_url?(target)

        result = url_parser.parse(target)
        return nil unless result

        ws = @runner.workspace(result.workspace)
        if result.thread?
          Result.new(workspace: ws, channel_id: result.channel_id, thread_ts: result.thread_ts, msg_ts: nil)
        else
          Result.new(workspace: ws, channel_id: result.channel_id, thread_ts: nil, msg_ts: result.msg_ts)
        end
      end

      def resolve_channel(workspace, name)
        cached = @cache.get_channel_id(workspace.name, name)
        return cached if cached

        fetch_and_cache_channel(workspace, name)
      end

      def fetch_and_cache_channel(workspace, name)
        channels = @runner.conversations_api(workspace.name).list['channels'] || []
        channel = channels.find { |c| c['name'] == name }
        raise ConfigError, "Channel not found: ##{name}" unless channel

        @cache.set_channel(workspace.name, name, channel['id'])
        channel['id']
      end

      def resolve_dm(workspace, username)
        user_id = find_user_id(workspace, username)
        raise ConfigError, "User not found: @#{username}" unless user_id

        api = @runner.conversations_api(workspace.name)
        response = api.open(users: user_id)
        response.dig('channel', 'id')
      end

      def find_user_id(workspace, username)
        api = @runner.users_api(workspace.name)
        response = api.list
        users = response['members'] || []

        user = users.find do |u|
          u['name'] == username ||
            u.dig('profile', 'display_name') == username ||
            u.dig('profile', 'real_name') == username
        end

        user&.dig('id')
      end
    end
  end
end
