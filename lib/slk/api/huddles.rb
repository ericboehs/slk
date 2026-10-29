# frozen_string_literal: true

module Slk
  module Api
    # Wrapper for Slack's undocumented huddles.* endpoints (the web client's).
    class Huddles
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      # The room for one call id: channels, live participants, has_ended.
      # Raises not_authorized for a huddle in a conversation the token
      # cannot see.
      def get(huddle_id)
        info(huddle_id)['huddle'] || {}
      end

      # The whole response, for `slk debug huddle`.
      def info(huddle_id)
        @api.post(@workspace, 'huddles.get', { huddle_id: huddle_id })
      end
    end
  end
end
