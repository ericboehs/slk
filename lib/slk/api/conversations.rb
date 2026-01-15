# frozen_string_literal: true

module Slk
  module Api
    # Wrapper for Slack conversations.* API endpoints
    class Conversations
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def list(cursor: nil, limit: 1000, types: 'public_channel,private_channel')
        params = { limit: limit, types: types }
        params[:cursor] = cursor if cursor
        @api.post(@workspace, 'conversations.list', params)
      end

      def history(channel:, limit: 20, cursor: nil, oldest: nil, latest: nil)
        params = { channel: channel, limit: limit }
        params[:cursor] = cursor if cursor
        params[:oldest] = oldest if oldest
        params[:latest] = latest if latest
        @api.post(@workspace, 'conversations.history', params)
      end

      def replies(channel:, timestamp:, limit: 100, cursor: nil)
        params = { channel: channel, ts: timestamp, limit: limit }
        params[:cursor] = cursor if cursor
        # Use form encoding - some workspaces (Enterprise Grid) require it
        @api.post_form(@workspace, 'conversations.replies', params)
      end

      def open(users:)
        user_list = Array(users).join(',')
        @api.post(@workspace, 'conversations.open', { users: user_list })
      end

      def mark(channel:, timestamp:)
        @api.post(@workspace, 'conversations.mark', { channel: channel, ts: timestamp })
      end

      def info(channel:)
        @api.post_form(@workspace, 'conversations.info', { channel: channel })
      end

      def members(channel:, cursor: nil, limit: 100)
        params = { channel: channel, limit: limit }
        params[:cursor] = cursor if cursor
        @api.post(@workspace, 'conversations.members', params)
      end
    end
  end
end
