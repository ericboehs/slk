# frozen_string_literal: true

require_relative 'messages'

module SlackCli
  module Commands
    class Thread < Messages
      def execute
        result = validate_options
        return result if result

        target = positional_args.first
        unless target
          error("Usage: slk thread <url>")
          return 1
        end

        # Thread command requires a URL
        url_parser = Support::SlackUrlParser.new
        unless url_parser.slack_url?(target)
          error("thread command requires a Slack URL")
          return 1
        end

        super
      end

      protected

      def default_options
        super.merge(
          limit: 1,
          limit_set: true,  # Prevent apply_default_limit from overriding
          threads: true
        )
      end

      def help_text
        help = Support::HelpFormatter.new("slk thread <url> [options]")
        help.description("View a message thread from a Slack URL.")

        help.section("USAGE") do |s|
          s.item("<slack_url>", "Slack message URL")
        end

        help.section("OPTIONS") do |s|
          s.option("--no-emoji", "Show :emoji: codes instead of unicode")
          s.option("--no-reactions", "Hide reactions")
          s.option("--no-names", "Skip user name lookups (faster)")
          s.option("--json", "Output as JSON")
          s.option("-v, --verbose", "Show debug information")
        end

        help.section("EXAMPLES") do |s|
          s.item("slk thread https://work.slack.com/archives/C123/p1234567890", "View thread")
        end

        help.render
      end
    end
  end
end
