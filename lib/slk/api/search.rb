# frozen_string_literal: true

module Slk
  module Api
    # Wrapper for Slack search.* API endpoints
    # Note: search.messages requires user tokens (xoxc/xoxs), NOT bot tokens (xoxb)
    class Search
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      # Search for messages across channels and DMs
      # @param query [String] Search query with optional modifiers (in:, from:, before:, after:, etc.)
      # @param count [Integer] Number of results per page (max 100)
      # @param page [Integer] Page number (1-indexed)
      # @param sort [String] Sort field: 'score' or 'timestamp'
      # @param sort_dir [String] Sort direction: 'asc' or 'desc'
      # @return [Hash] API response with messages.matches array
      def messages(query:, count: 20, page: 1, sort: 'timestamp', sort_dir: 'desc')
        @api.get(@workspace, 'search.messages', {
                   query: query,
                   count: [count, 100].min,
                   page: page,
                   sort: sort,
                   sort_dir: sort_dir
                 })
      end
    end
  end
end
