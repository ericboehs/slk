# frozen_string_literal: true

module Slk
  module Services
    # Finds a conversation id from a name typed as `#name`.
    #
    # Order: the channel cache, then every page of the conversations you
    # belong to (users.conversations: public and private channels plus group
    # DMs, so a named group DM such as "ifams review" resolves), then one page
    # of conversations.list for public channels you have not joined. That
    # last step is only one page, as before: the full workspace list runs to
    # thousands of channels at 100 per page.
    #
    # A channel wins over a named group DM with the same name. A group DM is
    # cached only after a full scan finds no channel of that name among yours.
    class ChannelLookup
      MEMBER_TYPES = 'public_channel,private_channel,mpim'
      MAX_PAGES = 50

      def initialize(runner:, cache_store:)
        @runner = runner
        @cache = cache_store
      end

      # @param workspace [Models::Workspace]
      # @param name [String] channel or group DM name, without the leading #
      # @return [String, nil] the conversation id, or nil if none matches
      def find_id(workspace, name)
        @cache.get_channel_id(workspace.name, name) || lookup(workspace, name)
      end

      private

      def lookup(workspace, name)
        channel = member_conversation(workspace, name) || listed_channel(workspace, name)
        return nil unless channel

        @cache.set_channel(workspace.name, channel['name'], channel['id'])
        channel['id']
      end

      def member_conversation(workspace, name)
        group_dm = nil
        each_member_page(workspace) do |conversations|
          conversations.each do |conversation|
            next unless name_matches?(conversation, name)
            return conversation unless conversation['is_mpim']

            group_dm ||= conversation
          end
        end
        group_dm
      end

      def each_member_page(workspace)
        api = @runner.users_api(workspace.name)
        cursor = nil
        MAX_PAGES.times do
          response = api.conversations(cursor: cursor, types: MEMBER_TYPES, exclude_archived: true)
          yield response['channels'] || []
          cursor = response.dig('response_metadata', 'next_cursor').to_s
          break if cursor.empty?
        end
      end

      def listed_channel(workspace, name)
        channels = @runner.conversations_api(workspace.name).list['channels'] || []
        channels.find { |channel| name_matches?(channel, name) }
      end

      # Channel names are lowercase; a group DM's name keeps whatever case
      # it was given, so "#IFAMS Review" and "#ifams review" both find it.
      def name_matches?(conversation, name)
        conversation['name'].to_s.casecmp?(name)
      end
    end
  end
end
