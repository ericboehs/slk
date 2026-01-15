# frozen_string_literal: true

require_relative 'messages'

module SlackCli
  module Commands
    # Views a message thread from a Slack URL
    class Thread < Messages
      def execute
        result = validate_options
        return result if result

        target = positional_args.first
        return usage_error unless target
        return url_required_error unless Support::SlackUrlParser.new.slack_url?(target)

        super
      end

      protected

      def usage_error
        error('Usage: slk thread <url>')
        1
      end

      def url_required_error
        error('thread command requires a Slack URL')
        1
      end

      def default_options
        super.merge(
          limit: 1,
          limit_set: true, # Prevent apply_default_limit from overriding
          threads: true
        )
      end

      def help_text
        help = Support::HelpFormatter.new('slk thread <url> [options]')
        help.description('View a message thread from a Slack URL.')
        add_usage_section(help)
        add_options_section(help)
        add_examples_section(help)
        help.render
      end

      private

      def add_usage_section(help)
        help.section('USAGE') { |s| s.item('<slack_url>', 'Slack message URL') }
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('--no-emoji', 'Show :emoji: codes instead of unicode')
          s.option('--no-reactions', 'Hide reactions')
          s.option('--no-names', 'Skip user name lookups (faster)')
          s.option('--json', 'Output as JSON')
          s.option('-v, --verbose', 'Show debug information')
        end
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |s|
          s.item('slk thread https://work.slack.com/archives/C123/p1234567890', 'View thread')
        end
      end
    end
  end
end
