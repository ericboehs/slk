# frozen_string_literal: true

module Slk
  module Support
    # Interactive terminal prompt utilities
    module InteractivePrompt
      module_function

      # Read a single character from the terminal
      def read_single_char
        if $stdin.tty?
          $stdin.raw(&:readchar)
        else
          $stdin.gets&.chomp
        end
      rescue Interrupt
        'q'
      end

      # Display a prompt and read a single character
      def prompt_for_action(prompt)
        print "\n#{prompt} > "
        input = read_single_char
        puts
        input
      end
    end
  end
end
