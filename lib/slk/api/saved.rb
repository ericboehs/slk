# frozen_string_literal: true

module Slk
  module Api
    # Thin wrapper for the Slack saved.list API endpoint
    # Used to fetch "Save for Later" items
    class Saved
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      # List saved items
      # @param filter [String] Filter type: 'saved', 'in_progress', 'completed', 'archived'
      # @param limit [Integer] Number of items to return (default: 15)
      # @param cursor [String, nil] Pagination cursor
      # @return [Hash] API response with 'ok' and 'saved_items' keys
      # @raise [ApiError] if the API call fails (network error, auth error, etc.)
      def list(filter: 'saved', limit: 15, cursor: nil)
        params = { filter: filter, limit: limit.to_s }
        params[:cursor] = cursor if cursor
        @api.post_form(@workspace, 'saved.list', params)
      end
    end
  end
end
