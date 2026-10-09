# frozen_string_literal: true

require 'stringio'
require_relative '../support/help_formatter'

module Slk
  module Commands
    # Displays saved "Later" items from Slack
    # rubocop:disable Metrics/ClassLength
    class Later < Base
      include Support::InlineImages
      include Support::AttachmentFetching
      include Support::ImagePreview

      BOOLEAN_FLAGS = {
        '--completed' => :completed,
        '--in-progress' => :in_progress,
        '--counts' => :counts,
        '--no-content' => :no_content,
        '--no-image-preview' => :no_image_preview,
        '--workspace-emoji' => :workspace_emoji
      }.freeze

      def execute
        result = validate_options
        return result if result

        workspace = target_workspaces.first
        fetch_and_display_later_items(workspace)
      rescue ApiError => e
        error("Failed to fetch saved items: #{e.message}")
        1
      end

      private

      def fetch_and_display_later_items(workspace)
        api = runner.saved_api(workspace.name)
        response = api.list(filter: filter_type, limit: @options[:limit])

        return error_result(response) unless response['ok']

        items = parse_items(response['saved_items'] || [])
        display_items(workspace, items)
        0
      end

      def error_result(response)
        error("Failed to fetch saved items: #{response['error']}")
        1
      end

      def parse_items(items_data)
        items_data.map { |data| Models::SavedItem.from_api(data) }
      end

      def filter_type
        if @options[:completed]
          'completed'
        elsif @options[:in_progress]
          'in_progress'
        else
          'saved'
        end
      end

      def display_items(workspace, items)
        if @options[:counts]
          display_counts(items)
        elsif @options[:json]
          output_json(build_json_output(workspace, items))
        else
          display_formatted(workspace, items)
        end
      end

      def display_counts(items)
        puts "Total: #{items.size}"
        puts "Overdue: #{items.count(&:overdue?)}" unless @options[:completed]
        puts "With due dates: #{items.count(&:due_date?)}"
      end

      # rubocop:disable Metrics/MethodLength
      def build_json_output(workspace, items)
        items.map do |item|
          json_item = {
            channel_id: item.channel_id,
            ts: item.ts,
            state: item.state,
            date_created: item.date_created,
            date_due: item.date_due,
            date_completed: item.date_completed,
            overdue: item.overdue?
          }

          # Fetch message content unless --no-content
          unless @options[:no_content]
            message = fetch_message_content(workspace, item)
            json_item[:message] = message if message
            add_json_file_paths(json_item, workspace, item, message)
          end

          json_item
        end
      end
      # rubocop:enable Metrics/MethodLength

      def add_json_file_paths(json_item, workspace, item, message)
        return unless @options[:fetch_attachments]

        paths = attachment_paths_for(workspace, item, message)
        json_item[:file_paths] = paths unless paths.empty?
      end

      def display_formatted(workspace, items)
        if items.empty?
          puts 'No saved items found.'
          return
        end

        @fetch_failures = 0
        @displayed_messages = []
        display_each_item(workspace, items)
        show_fetch_failure_summary
        print_file_summary(@displayed_messages) unless @options[:fetch_attachments]
      end

      def display_each_item(workspace, items)
        printer = buffered_display? ? method(:display_item_buffered) : method(:display_item_direct)
        items.each do |item|
          message = @options[:no_content] ? nil : fetch_message_content(workspace, item)
          printer.call(item, workspace, message, attachment_paths_for(workspace, item, message))
        end
      end

      def display_item_direct(item, workspace, message, file_paths)
        @direct_formatter ||= build_formatter(output)
        format_item(@direct_formatter, item, workspace, message, file_paths)
      end

      # Capture one item's output, then reprint it line by line so workspace
      # emoji and downloaded images can be drawn inline as each item arrives.
      def display_item_buffered(item, workspace, message, file_paths)
        buffer = StringIO.new
        format_item(build_formatter(create_buffer_output(buffer)), item, workspace, message, file_paths)
        previews = preview_paths(file_paths)
        buffer.string.each_line do |line|
          print_buffered_line(line.chomp, workspace)
          print_line_previews(line, previews)
        end
      end

      def format_item(formatter, item, workspace, message, file_paths)
        formatter.display_item(item, workspace, message: message, width: display_width,
                                                truncate: @options[:truncate], file_paths: file_paths)
      end

      def print_buffered_line(line, workspace)
        if workspace_emoji_images?
          print_with_workspace_emoji(line, workspace)
        else
          puts line
        end
      end

      # Draw a preview under the [File: ...] / [Image: ...] line that names it
      def print_line_previews(line, previews)
        previews.each do |path|
          next unless line.include?("[File: #{path}]") || line.include?("[Image: #{path}]")

          previews.delete(path)
          print_image_preview(path)
        end
      end

      def preview_paths(file_paths)
        return [] unless attachment_previews?

        file_paths.values.uniq.select { |path| previewable_image?(path) }
      end

      # Workspace emoji are terminal escape sequences, so skip them in markdown mode
      def workspace_emoji_images?
        @options[:workspace_emoji] && !@options[:markdown] && inline_images_supported?
      end

      def attachment_previews?
        return false unless @options[:fetch_attachments]
        return false if @options[:markdown] || @options[:quiet] || @options[:no_image_preview]

        image_previews_supported?
      end

      def buffered_display?
        workspace_emoji_images? || attachment_previews?
      end

      # Track the message for the "N files not downloaded" summary and, with
      # --fetch-attachments, download its files/images to the local cache.
      # @return [Hash] file_id / "att_<ts>_<idx>" => local path
      def attachment_paths_for(workspace, item, message)
        return {} unless message

        model = Models::Message.from_api(message, channel_id: item.channel_id)
        @displayed_messages&.push(model)
        return {} unless @options[:fetch_attachments]

        fetch_attachment_files([model], workspace)
      end

      def show_fetch_failure_summary
        return if @fetch_failures.zero?

        output.puts output.gray("Note: Could not load content for #{@fetch_failures} item(s). Use -v for details.")
      end

      def display_width
        @options[:width]
      end

      def build_formatter(out)
        Formatters::SavedItemFormatter.new(
          output: out,
          mention_replacer: runner.mention_replacer,
          text_processor: runner.text_processor,
          on_debug: ->(msg) { debug(msg) }
        )
      end

      # Create a buffer output using the same class as the main output
      # This ensures markdown mode works correctly with workspace emoji buffering
      def create_buffer_output(buffer)
        if @options[:markdown]
          Formatters::MarkdownOutput.new(io: buffer, err: $stderr)
        else
          Formatters::Output.new(io: buffer, err: $stderr, color: $stdout.tty?)
        end
      end

      def fetch_message_content(workspace, item)
        return nil unless item.ts && item.channel_id

        result = message_resolver(workspace).fetch_by_ts(item.channel_id, item.ts)
        @fetch_failures += 1 if result.nil?
        result
      end

      def message_resolver(workspace)
        Services::MessageResolver.new(
          conversations_api: runner.conversations_api(workspace.name),
          on_debug: ->(msg) { debug(msg) }
        )
      end

      protected

      def default_options
        super.merge(
          limit: 15,
          completed: false,
          in_progress: false,
          counts: false,
          no_content: false,
          no_image_preview: false,
          truncate: false,
          workspace_emoji: false
        )
      end

      def handle_option(arg, args, remaining)
        if %w[-n --limit].include?(arg)
          @options[:limit] = args.shift.to_i
        elsif BOOLEAN_FLAGS.key?(arg)
          @options[BOOLEAN_FLAGS[arg]] = true
        else
          super
        end
      end

      # Override to intercept --no-wrap before base class handles it
      def parse_single_option(arg, args, remaining)
        if arg == '--no-wrap'
          @options[:truncate] = true
          @options[:width] ||= 140
        else
          super
        end
      end

      def default_width
        nil
      end

      def help_text
        help = Support::HelpFormatter.new('slk later [options]')
        help.description('Show saved "Later" items from Slack.')
        help.note('Set SLK_IMAGE_PREVIEW=0 to always skip inline image previews.')
        add_options_section(help)
        help.render
      end

      # rubocop:disable Metrics/MethodLength
      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-n, --limit N', 'Number of items (default: 15)')
          s.option('--completed', 'Show completed items instead')
          s.option('--in-progress', 'Show in-progress items')
          s.option('--counts', 'Show summary counts only')
          s.option('--no-content', 'Skip fetching message text')
          s.option('--fetch-attachments', 'Download files to ~/.cache/slk/files/ (inline image previews need chafa)')
          s.option('--no-image-preview', 'Download attachments but skip inline image previews')
          s.option('--workspace-emoji', 'Show workspace emoji as inline images')
          s.option('--no-emoji', 'Show :emoji: codes instead of unicode')
          s.option('--width N', 'Wrap text at N columns')
          s.option('--no-wrap', 'Truncate to single line instead of wrapping')
          add_common_options(s)
        end
      end

      # rubocop:enable Metrics/MethodLength

      def add_common_options(section)
        section.option('--json', 'Output as JSON')
        section.option('-w, --workspace', 'Specify workspace')
        section.option('-v, --verbose', 'Show debug information')
        section.option('-q, --quiet', 'Suppress output')
      end

      # Print text, replacing workspace emoji codes with inline images
      def print_with_workspace_emoji(text, workspace)
        print_line_with_emoji_images(text, workspace)
      end

      def print_line_with_emoji_images(text, workspace)
        emoji_pattern = /:([a-zA-Z0-9_+-]+):/
        parts = text.split(emoji_pattern)

        parts.each_with_index { |part, i| print_emoji_part(part, i, workspace) }
        puts
      end

      def print_emoji_part(part, index, workspace)
        if index.odd?
          print_emoji_or_code(part, workspace)
        else
          print part
        end
      end

      def print_emoji_or_code(emoji_name, workspace)
        emoji_path = find_workspace_emoji(workspace.name, emoji_name)
        if emoji_path
          print_inline_image(emoji_path, height: 1)
          print ' ' unless in_tmux?
        else
          print ":#{emoji_name}:"
        end
      end

      def find_workspace_emoji(workspace_name, emoji_name)
        return nil if emoji_name.empty?

        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir
        workspace_dir = File.join(emoji_dir, workspace_name)
        return nil unless Dir.exist?(workspace_dir)

        Dir.glob(File.join(workspace_dir, "#{emoji_name}.*")).first
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
