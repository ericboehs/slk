# frozen_string_literal: true

module Slk
  module Services
    # Header label for a group DM in unread and catchup. A named group DM
    # shows its name ("#ifams review"); any other shows the people in it
    # besides you ("@Ada Lovelace, Grace Hopper") rather than the opaque
    # mpdm-* slug. One conversations.info per chat, remembered for the run.
    class GroupDmLabel
      def initialize(runner:, on_debug: nil)
        @runner = runner
        @on_debug = on_debug
        @labels = {}
        @self_ids = {}
      end

      # @return [String] "#name", "@names", or "#<channel id>" if Slack refuses
      def label(workspace, channel_id)
        @labels[[workspace.name, channel_id]] ||= fetch_label(workspace, channel_id)
      end

      private

      def fetch_label(workspace, channel_id)
        channel = @runner.conversations_api(workspace.name).info(channel: channel_id)['channel'] || {}
        label_for(workspace, channel) || "##{channel_id}"
      rescue ApiError => e
        @on_debug&.call("Group DM lookup failed for #{channel_id}: #{e.message}")
        "##{channel_id}"
      end

      def label_for(workspace, channel)
        named = Support::GroupDmName.custom(channel)
        return "##{named}" if named

        names = member_names(workspace, channel['members'] || [])
        return "@#{names.join(', ')}" if names.any?

        "##{channel['name']}" unless channel['name'].to_s.empty?
      end

      def member_names(workspace, members)
        self_id = self_user_id(workspace)
        others = members.reject { |id| id == self_id }
        others = members if others.empty?
        others.map { |id| user_name(workspace, id) }
      end

      def user_name(workspace, user_id)
        UserLookup.new(cache_store: @runner.cache_store, workspace: workspace,
                       api_client: @runner.api_client, on_debug: @on_debug).resolve_name_or_bot(user_id) || user_id
      end

      # Same meta key the sent and who commands use, so one auth.test serves all.
      def self_user_id(workspace)
        @self_ids.fetch(workspace.name) do
          @self_ids[workspace.name] = @runner.cache_store.get_meta(workspace.name, 'self_user_id') ||
                                      fetch_self_user_id(workspace)
        end
      end

      def fetch_self_user_id(workspace)
        id = @runner.client_api(workspace.name).auth_test['user_id']
        @runner.cache_store.set_meta(workspace.name, 'self_user_id', id) if id
        id
      rescue ApiError => e
        @on_debug&.call("Could not identify self in #{workspace.name}: #{e.message}")
        nil
      end
    end
  end
end
