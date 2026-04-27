# frozen_string_literal: true

module Slk
  module Services
    # Disambiguates between multiple matching users. Prompts at a TTY; raises
    # ApiError in non-interactive contexts so callers don't silently get the
    # wrong user when name resolution is ambiguous.
    class UserPicker
      def initialize(stdin: $stdin, prompt_io: $stderr)
        @stdin = stdin
        @prompt_io = prompt_io
      end

      def pick(matches)
        return matches.first['id'] if matches.size == 1

        unless interactive?
          raise ApiError,
                "Ambiguous match (#{matches.size} users): #{ids(matches).join(', ')}. " \
                'Use --pick N or --all to disambiguate non-interactively.'
        end

        list(matches)
        matches[read_index(matches.size)]['id']
      end

      private

      def interactive?
        @stdin.respond_to?(:tty?) && @stdin.tty?
      end

      def list(matches)
        @prompt_io.puts('Multiple users match — pick one:')
        matches.each_with_index { |u, i| @prompt_io.puts("  [#{i + 1}] #{describe(u)}") }
      end

      def describe(user)
        profile = user['profile'] || {}
        name = profile['real_name'] || profile['display_name'] || user['name']
        suffix = profile['title'].to_s.empty? ? '' : " — #{profile['title']}"
        "#{name} (#{user['id']})#{suffix}#{flag_suffix(user)}"
      end

      def flag_suffix(user)
        flags = []
        flags << 'deactivated' if user['deleted']
        flags << 'bot' if user['is_bot']
        flags.empty? ? '' : " [#{flags.join(', ')}]"
      end

      def ids(matches)
        matches.map { |u| u['id'] }
      end

      def read_index(count)
        loop do
          @prompt_io.print("Choice [1-#{count}]: ")
          choice = @stdin.gets&.strip
          raise ApiError, 'No selection made' if choice.nil? || choice.empty?

          n = Integer(choice, exception: false)
          return n - 1 if n&.between?(1, count)
        end
      end
    end
  end
end
