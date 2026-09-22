# frozen_string_literal: true

module Slk
  module Services
    # Resolves sent-conversation destinations while retaining raw channel IDs
    # and names in JSON. Group DMs need member lookup: their Slack name is an
    # opaque mpdm-* slug, not a user ID that MentionReplacer can resolve.
    class SentChannelLabel
      USER_ID_PATTERN = /\A[UW][A-Z0-9]+\z/

      def initialize(runner:)
        @runner = runner
        @labels = {}
      end

      # rubocop:disable Metrics/ParameterLists
      def label(workspace:, type:, name:, channel_id:, self_user_id: nil, self_username: nil)
        key = [workspace.name, channel_id, self_user_id]
        @labels[key] ||= if type == 'mpim'
                           group_label(workspace, channel_id, name, self_user_id, self_username)
                         else
                           @runner.search_formatter.channel_label_for(type, name, workspace)
                         end
      end

      # rubocop:enable Metrics/ParameterLists

      private

      def group_label(workspace, channel_id, name, self_user_id, self_username)
        names = group_member_names(workspace, channel_id, self_user_id)
        return "@#{names.join(', ')}" if names.any?

        fallback_group_label(name, self_username)
      rescue ApiError
        fallback_group_label(name, self_username)
      end

      def group_member_names(workspace, channel_id, self_user_id)
        members = @runner.conversations_api(workspace.name).info(channel: channel_id).dig('channel', 'members') || []
        names = members.reject { |id| id == self_user_id }.map { |id| resolve_name(workspace, id) }
        names.any? { |value| value.match?(USER_ID_PATTERN) } ? [] : names
      end

      def resolve_name(workspace, user_id)
        Services::UserLookup.new(cache_store: @runner.cache_store, workspace: workspace,
                                 api_client: @runner.api_client).resolve_name_or_bot(user_id) || user_id
      end

      def fallback_group_label(name, self_username)
        handles = name.to_s.sub(/\Ampdm-/, '').sub(/-\d+\z/, '').split('--')
        people = handles.reject { |handle| normalized_handle(handle) == normalized_handle(self_username) }
        people = handles if people.empty?
        "@#{people.map { |handle| pretty_handle(handle) }.join(', ')}"
      end

      def normalized_handle(handle)
        handle.to_s.downcase.gsub(/[^a-z0-9]/, '')
      end

      def pretty_handle(handle)
        handle.tr('._-', ' ').split.map(&:capitalize).join(' ')
      end
    end
  end
end
