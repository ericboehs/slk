# frozen_string_literal: true

module SlackCli
  module Api
    class Conversations
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def list(cursor: nil, limit: 1000, types: "public_channel,private_channel")
        params = { limit: limit, types: types }
        params[:cursor] = cursor if cursor
        @api.post(@workspace, "conversations.list", params)
      end

      def history(channel:, limit: 20, cursor: nil, oldest: nil, latest: nil)
        params = { channel: channel, limit: limit }
        params[:cursor] = cursor if cursor
        params[:oldest] = oldest if oldest
        params[:latest] = latest if latest
        @api.post(@workspace, "conversations.history", params)
      end

      def replies(channel:, ts:, limit: 100, cursor: nil)
        params = { channel: channel, ts: ts, limit: limit }
        params[:cursor] = cursor if cursor
        @api.post(@workspace, "conversations.replies", params)
      end

      def open(users:)
        user_list = Array(users).join(",")
        @api.post(@workspace, "conversations.open", { users: user_list })
      end

      def mark(channel:, ts:)
        @api.post(@workspace, "conversations.mark", { channel: channel, ts: ts })
      end

      def info(channel:)
        @api.post_form(@workspace, "conversations.info", { channel: channel })
      end

      def members(channel:, cursor: nil, limit: 100)
        params = { channel: channel, limit: limit }
        params[:cursor] = cursor if cursor
        @api.post(@workspace, "conversations.members", params)
      end
    end
  end
end
