# frozen_string_literal: true

module SlackCli
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
        lines = []
        lines << "USAGE: #{@usage}"
        lines << ""

        if @description
          lines << @description
        end

        @notes.each do |note|
          lines << note
        end

        lines << "" if @description || @notes.any?

        @sections.each do |section|
          lines << "#{section.title}:"
          lines.concat(section.render)
          lines << ""
        end

        # Remove trailing blank line
        lines.pop if lines.last == ""

        lines.join("\n")
      end

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

          # Calculate max width of left column
          max_left = @items
            .reject { |type, _, _| type == :text }
            .map { |_, left, _| left.length }
            .max || 0

          # Add padding (2 spaces between columns)
          padding = 2

          @items.map do |type, left, right|
            case type
            when :text
              "  #{left}"
            when :example
              if right
                "  #{left.ljust(max_left + padding)}#{right}"
              else
                "  #{left}"
              end
            else
              "  #{left.ljust(max_left + padding)}#{right}"
            end
          end
        end
      end
    end
  end
end
