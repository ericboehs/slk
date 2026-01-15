# frozen_string_literal: true

module Slk
  module Services
    # Searches standard and workspace custom emoji
    class EmojiSearcher
      def initialize(cache_dir:, emoji_dir:, on_debug: nil)
        @cache_dir = cache_dir
        @emoji_dir = emoji_dir
        @on_debug = on_debug
      end

      # Search emoji by pattern
      # @param query [String] Search query
      # @param workspaces [Array<Workspace>] Workspaces to search (nil for all)
      # @return [Hash] Results grouped by source
      def search(query, workspaces: [])
        pattern = Regexp.new(Regexp.escape(query), Regexp::IGNORECASE)
        results = []

        # Search standard emoji
        results.concat(search_standard(pattern))

        # Search workspace custom emoji
        workspaces.each do |workspace|
          results.concat(search_workspace(workspace, pattern))
        end

        # Group by source
        results.group_by { |r| r[:source] }
      end

      # Search standard emoji only
      # @param pattern [Regexp] Pattern to match
      # @return [Array<Hash>] Matching emoji with :name, :char, :source
      def search_standard(pattern)
        gemoji = load_gemoji
        return [] unless gemoji

        gemoji.filter_map do |name, char|
          { name: name, char: char, source: 'standard' } if name.match?(pattern)
        end
      end

      # Search a workspace's custom emoji
      # @param workspace [Workspace] Workspace to search
      # @param pattern [Regexp] Pattern to match
      # @return [Array<Hash>] Matching emoji with :name, :path, :source
      def search_workspace(workspace, pattern)
        workspace_dir = File.join(@emoji_dir, workspace.name)
        return [] unless Dir.exist?(workspace_dir)

        Dir.glob(File.join(workspace_dir, '*')).filter_map do |filepath|
          name = File.basename(filepath, '.*')
          { name: name, path: filepath, source: workspace.name } if name.match?(pattern)
        end
      end

      private

      def load_gemoji
        gemoji_path = File.join(@cache_dir, 'gemoji.json')
        return nil unless File.exist?(gemoji_path)

        JSON.parse(File.read(gemoji_path))
      rescue JSON::ParserError
        @on_debug&.call('Standard emoji cache corrupted, skipping')
        nil
      end
    end
  end
end
