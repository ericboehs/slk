# frozen_string_literal: true

module Slk
  module Services
    # Interactive disambiguation when a name resolves to multiple users.
    # Lists matches with index + flags (deactivated, bot) and reads a choice.
    class UserPicker
      def initialize(output:, stdin: $stdin, prompt_io: $stderr)
        @output = output
        @stdin = stdin
        @prompt_io = prompt_io
      end

      # Returns the chosen user_id from `matches` (an Array of users.list user
      # hashes). Falls back to the first match when not on a TTY.
      def pick(matches)
        return matches.first['id'] if matches.size == 1
        return matches.first['id'] unless interactive?

        list(matches)
        matches[read_index(matches.size)]['id']
      end

      private

      def interactive?
        @stdin.respond_to?(:tty?) && @stdin.tty?
      end

      def list(matches)
        @output.puts('Multiple users match — pick one:')
        matches.each_with_index { |u, i| @output.puts("  [#{i + 1}] #{describe(u)}") }
      end

      def describe(user)
        profile = user['profile'] || {}
        name = profile['real_name'] || profile['display_name'] || user['name']
        suffix = profile['title'].to_s.empty? ? '' : " — #{profile['title']}"
        tag = flag_suffix(user)
        "#{name} (#{user['id']})#{suffix}#{tag}"
      end

      def flag_suffix(user)
        flags = []
        flags << 'deactivated' if user['deleted']
        flags << 'bot' if user['is_bot']
        flags.empty? ? '' : " [#{flags.join(', ')}]"
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
