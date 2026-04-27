# frozen_string_literal: true

module Slk
  module Commands
    # Display a Slack user profile (teems-style compact card by default).
    # Examples:
    #   slk who                  # self
    #   slk who @alex
    #   slk who alice
    #   slk who Uxxx --full
    #   slk who --json
    class Who < Base
      def execute
        result = validate_options
        return result if result

        run
      rescue ApiError => e
        error("API error: #{e.message}")
        1
      end

      protected

      def handle_option(arg, _args, _remaining)
        case arg
        when '--full' then @options[:full] = true
        when '--no-cache', '--refresh' then @options[:refresh] = true
        else return super
        end
        true
      end

      def help_text
        <<~HELP
          slk who [target]

          Show a Slack user profile.

          TARGET
            (none)           Self
            @handle | name   Resolved via user cache
            Uxxx             Raw user ID

          OPTIONS
            --full           Section-grouped layout (Contact, People, About me)
            --json           Raw JSON output
            --refresh        Bypass cache (TODO once cache lands)
        HELP
      end

      private

      def run
        workspace = runner.workspace(@options[:workspace])
        profile = load_profile(workspace)
        return output_json_profile(profile) if @options[:json]

        render(profile)
        0
      end

      def load_profile(workspace)
        user_id = resolve_user_id(workspace)
        runner.profile_resolver(workspace.name, refresh: @options[:refresh])
              .resolve_with_people(user_id)
      end

      def render(profile)
        formatter = Formatters::ProfileFormatter.new(
          output: output, emoji_replacer: runner.emoji_replacer
        )
        @options[:full] ? formatter.full(profile) : formatter.compact(profile)
      end

      def output_json_profile(profile)
        output_json(profile.to_h.merge(
                      custom_fields: profile.visible_fields.map(&:to_h),
                      sections: profile.sections,
                      resolved_users: profile.resolved_users.transform_values(&:to_h)
                    ))
        0
      end

      def resolve_user_id(workspace)
        target = positional_args.first
        return self_user_id(workspace) if target.nil? || target == 'me'
        return target if target.match?(/\A[UW][A-Z0-9]+\z/)

        lookup_id(workspace, target.delete_prefix('@')) ||
          (raise ApiError, "Could not resolve user: #{target}")
      end

      def lookup_id(workspace, name)
        Services::UserLookup.new(
          cache_store: cache_store,
          workspace: workspace,
          api_client: api_client,
          on_debug: ->(msg) { output.debug(msg) }
        ).find_id_by_name(name)
      end

      def self_user_id(workspace)
        cached = cache_store.get_meta(workspace.name, 'self_user_id')
        return cached if cached

        user_id = Api::Client.new(api_client, workspace).auth_test['user_id']
        cache_store.set_meta(workspace.name, 'self_user_id', user_id) if user_id
        user_id
      end
    end
  end
end
