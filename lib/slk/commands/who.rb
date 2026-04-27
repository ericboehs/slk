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

      def handle_option(arg, args, _remaining)
        case arg
        when '--full' then @options[:full] = true
        when '--no-cache', '--refresh' then @options[:refresh] = true
        when '--all' then @options[:all] = true
        when '--pick' then @options[:pick] = Integer(args.shift, exception: false)
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
            --refresh        Bypass cache
            --all            Render every match (skips the disambiguation prompt)
            --pick N         Auto-select match N when a name resolves to multiple
        HELP
      end

      private

      def run
        workspace = runner.workspace(@options[:workspace])
        profiles = resolve_profiles(workspace)
        return output_json_profiles(profiles) if @options[:json]

        render_profiles(profiles)
        0
      end

      def resolve_profiles(workspace)
        resolver = Services::WhoTargetResolver.new(
          workspace: workspace, cache_store: cache_store,
          api_client: api_client, output: output, options: @options
        )
        resolver.resolve(positional_args.first).map { |id| load_profile(workspace, id) }
      end

      def load_profile(workspace, user_id)
        runner.profile_resolver(workspace.name, refresh: @options[:refresh])
              .resolve_with_people(user_id)
      end

      def render_profiles(profiles)
        profiles.each_with_index do |profile, idx|
          output.puts(output.gray('—' * 40)) if idx.positive?
          render(profile)
        end
      end

      def render(profile)
        formatter = Formatters::ProfileFormatter.new(
          output: output, emoji_replacer: runner.emoji_replacer
        )
        @options[:full] ? formatter.full(profile) : formatter.compact(profile)
      end

      def output_json_profiles(profiles)
        payload = profiles.map { |p| profile_payload(p) }
        output_json(profiles.size == 1 ? payload.first : payload)
        0
      end

      def profile_payload(profile)
        profile.to_h.merge(
          custom_fields: profile.visible_fields.map(&:to_h),
          sections: profile.sections,
          resolved_users: profile.resolved_users.transform_values(&:to_h)
        )
      end
    end
  end
end
