# frozen_string_literal: true

module Slk
  module Services
    # Resolves the positional target for `slk who` into one or more user_ids.
    class WhoTargetResolver
      def initialize(workspace:, cache_store:, api_client:, output:, options:)
        @workspace = workspace
        @cache_store = cache_store
        @api_client = api_client
        @output = output
        @options = options
      end

      def resolve(target)
        return [self_user_id] if target.nil? || target == 'me'
        return [target] if target.match?(/\A[UW][A-Z0-9]+\z/)

        ids = resolve_by_name(target.delete_prefix('@'))
        ids || (raise ApiError, "Could not resolve user: #{target}")
      end

      private

      def resolve_by_name(name)
        matches = lookup.find_all_by_name(name)
        return select(matches) if matches.any?

        cached = @cache_store.get_user_id_by_name(@workspace.name, name)
        cached ? [cached] : nil
      end

      def select(matches)
        return matches.map { |u| u['id'] } if @options[:all]
        return [pick_by_index(matches)] if @options[:pick]

        [UserPicker.new(output: @output).pick(matches)]
      end

      def pick_by_index(matches)
        idx = @options[:pick]
        raise ApiError, "--pick #{idx} out of range (got #{matches.size} matches)" unless idx&.between?(1, matches.size)

        matches[idx - 1]['id']
      end

      def lookup
        UserLookup.new(
          cache_store: @cache_store, workspace: @workspace,
          api_client: @api_client, on_debug: ->(msg) { @output.debug(msg) }
        )
      end

      def self_user_id
        cached = @cache_store.get_meta(@workspace.name, 'self_user_id')
        return cached if cached

        user_id = Api::Client.new(@api_client, @workspace).auth_test['user_id']
        @cache_store.set_meta(@workspace.name, 'self_user_id', user_id) if user_id
        user_id
      end
    end
  end
end
