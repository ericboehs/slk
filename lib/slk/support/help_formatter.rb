# frozen_string_literal: true

module Slk
  module Support
    # Formats help text with auto-aligned columns
    #
    # Example usage:
    #   help = HelpFormatter.new("slk status [text] [emoji] [options]")
    #   help.description("Get or set your Slack status.")
    #   help.note("GET shows all workspaces by default. SET applies to primary only.")
    #
    #   help.section("EXAMPLES") do |s|
    #     s.example("slk status", "Show status (all workspaces)")
    #     s.example("slk status clear", "Clear status")
    #   end
    #
    #   help.section("OPTIONS") do |s|
    #     s.option("-n, --limit N", "Messages per channel (default: 10)")
    #     s.option("--muted", "Include muted channels")
    #   end
    #
    #   puts help.render
    #
    class HelpFormatter
      def initialize(usage)
        @usage = usage
        @description = nil
        @notes = []
        @sections = []
      end

      def description(text)
        @description = text
        self
      end

      def note(text)
        @notes << text
        self
      end

      def section(title, &block)
        section = Section.new(title)
        block.call(section)
        @sections << section
        self
      end

      def render
        lines = build_header
        lines.concat(build_sections)
        lines.pop if lines.last == ''
        lines.join("\n")
      end

      private

      def build_header
        lines = ["USAGE: #{@usage}", '']
        lines << @description if @description
        @notes.each { |note| lines << note }
        lines << '' if @description || @notes.any?
        lines
      end

      def build_sections
        @sections.flat_map { |section| ["#{section.title}:", *section.render, ''] }
      end

      # Represents a section within help output (OPTIONS, EXAMPLES, etc.)
      class Section
        attr_reader :title

        def initialize(title)
          @title = title
          @items = []
        end

        def option(flags, description)
          @items << [:option, flags, description]
          self
        end

        def action(name, description)
          @items << [:action, name, description]
          self
        end

        def example(command, description = nil)
          @items << [:example, command, description]
          self
        end

        def item(left, right)
          @items << [:item, left, right]
          self
        end

        def text(content)
          @items << [:text, content, nil]
          self
        end

        def render
          return [] if @items.empty?

          max_left = calculate_max_left_width
          @items.map { |type, left, right| format_item(type, left, right, max_left) }
        end

        private

        def calculate_max_left_width
          @items.reject { |type, _, _| type == :text }.map { |_, left, _| left.length }.max || 0
        end

        def format_item(type, left, right, max_left)
          case type
          when :text then "  #{left}"
          when :example then format_example(left, right, max_left)
          else "  #{left.ljust(max_left + 2)}#{right}"
          end
        end

        def format_example(left, right, max_left)
          right ? "  #{left.ljust(max_left + 2)}#{right}" : "  #{left}"
        end
      end
    end
  end
end
