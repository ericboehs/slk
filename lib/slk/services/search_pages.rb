# frozen_string_literal: true

module Slk
  module Services
    # Walks search.messages pages without silently dropping results at Slack's
    # 100-result page boundary. A limit caps results per workspace; nil fetches all.
    class SearchPages
      def initialize(search_api)
        @search_api = search_api
      end

      # The loop tracks both the API page and the requested result cap.
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def fetch(query:, limit: nil, page: 1, sort_dir: 'desc')
        results = []
        first_pagination = nil
        matches = []
        current = page
        count = limit ? [limit, 100].min : 100

        loop do
          # Keep count fixed: Slack computes page offsets from count. Changing
          # 100 to 50 for the last page would repeat rows from the first page.
          response = @search_api.messages(query: query, count: count, page: current, sort_dir: sort_dir)
          messages = response.fetch('messages', {})
          matches = messages.fetch('matches', [])
          pagination = messages.fetch('pagination', {})
          first_pagination ||= pagination
          remaining = limit ? limit - results.length : matches.length
          results.concat(matches.first(remaining).map { |match| Models::SearchResult.from_api(match) })
          break if matches.empty?

          if !pagination['page_count'] && matches.length >= count
            raise ApiError, 'Search response omitted pagination; cannot guarantee complete results'
          end
          break if limit && results.length >= limit
          break unless pagination['page_count'] && current < pagination['page_count'].to_i

          current += 1
        end

        { results: results, pagination: first_pagination || {},
          truncated: truncated?(first_pagination, page, current, results, matches, limit) }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private

      # A short limit can cut off a page even when Slack omits total_count.
      # The page offset and last batch are needed when total_count is missing.
      # rubocop:disable Metrics/ParameterLists
      def truncated?(pagination, page, current, results, matches, limit)
        return false unless limit

        offset = (page - 1) * [limit, 100].min
        total = pagination['total_count']
        return total.to_i > offset + results.length if total

        matches.length > [limit - ((current - page) * [limit, 100].min), 0].max ||
          pagination['page_count'].to_i > current
      end
      # rubocop:enable Metrics/ParameterLists
    end
  end
end
