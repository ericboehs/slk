# frozen_string_literal: true

module Slk
  module Commands
    # Walk the Slack org chart by following Supervisor custom profile fields.
    # Examples:
    #   slk org                        # self, supervisors up to depth 3
    #   slk org @alex                  # alex's chain
    #   slk org Uxxx --depth 5
    #   slk org --down                 # reports (best-effort, requires reindex for completeness)
    class Org < Base
      DEFAULT_DEPTH = 5

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
        when '--up' then @options[:direction] = :up
        when '--down' then @options[:direction] = :down
        when '--depth' then @options[:depth] = args.shift.to_i
        else return super
        end
        true
      end

      def help_text
        <<~HELP
          slk org [target]

          Walk the Slack org chart by Supervisor field.

          OPTIONS
            --up               Walk supervisors upward (default)
            --down             Show direct reports (best-effort, see note)
            --depth N          Levels to walk (default #{DEFAULT_DEPTH})

          NOTES
            --down currently scans cached profiles only. Run `slk who` on a
            user to seed their profile in cache; full crawl support is TODO.
        HELP
      end

      private

      def run
        workspace = runner.workspace(@options[:workspace])
        resolver = runner.profile_resolver(workspace.name, refresh: @options[:refresh])
        user_id = resolve_user_id(workspace)
        target = resolver.resolve(user_id)
        @self_user_id = self_user_id(workspace)

        case @options[:direction] || :up
        when :up then render_up(resolver, target)
        when :down then render_down(target)
        end
        0
      end

      def render_up(resolver, target)
        chain = resolver.resolve_chain_up(target.user_id, depth: @options[:depth] || DEFAULT_DEPTH)
        if chain.empty?
          info("No supervisor on #{target.best_name}'s profile.")
          return
        end

        chain.reverse_each.with_index do |profile, depth|
          render_node(profile, depth, you: profile.user_id == @self_user_id)
        end
        render_node(target, chain.size, you: target.user_id == @self_user_id)
      end

      def render_down(target)
        warn('slk org --down is best-effort against cached profiles only.')
        warn('Run `slk who <user>` to seed their profile, or wait for `slk org reindex` (TODO).')
        info("Direct reports for #{target.best_name}: lookup not yet wired (Phase 4).")
      end

      def render_node(profile, depth, you: false)
        prefix = depth.zero? ? '' : "#{'  ' * depth}└─ "
        marker = you ? output.bold(' ← you') : ''
        title = profile.title.to_s.empty? ? '' : " — #{output.gray(profile.title)}"
        output.puts("#{prefix}#{profile.best_name}#{title}#{marker}")
      end

      def resolve_user_id(workspace)
        target = positional_args.first
        return self_user_id(workspace) if target.nil? || target == 'me'
        return target if target.match?(/\A[UW][A-Z0-9]+\z/)

        Services::UserLookup.new(
          cache_store: cache_store,
          workspace: workspace,
          api_client: api_client,
          on_debug: ->(msg) { output.debug(msg) }
        ).find_id_by_name(target.delete_prefix('@')) ||
          (raise ApiError, "Could not resolve user: #{target}")
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
