# frozen_string_literal: true

module Slk
  module Formatters
    # Formats search results for terminal display
    class SearchFormatter
      def initialize(output:, mention_replacer:, text_processor:)
        @output = output
        @mentions = mention_replacer
        @text_processor = text_processor
      end

      # Display a list of search results
      def display_all(results, workspace, options: {})
        return @output.puts 'No results found.' if results.empty?

        results.each_with_index do |result, index|
          display_result(result, workspace, options)
          @output.puts if index < results.length - 1
        end
      end

      # Display a single search result
      def display_result(result, workspace, options = {})
        timestamp = @output.blue("[#{format_time(result.timestamp)}]")
        channel = @output.cyan(display_channel_label(result, workspace, options))
        user = @output.bold("#{resolve_user(result, workspace)}:")
        text = prepare_text(result.text, workspace, options)

        workspace_label = workspace_prefix(workspace, options)
        @output.puts "#{timestamp} #{workspace_label}#{channel} #{user} #{text}"
        display_files(result.files) if result.files&.any?
      end

      # Channel label used by search timelines and per-channel summaries.
      def channel_label(result, workspace)
        channel_label_for(result.channel_type, result.channel_name, workspace)
      end

      def channel_label_for(type, name, workspace)
        if %w[im mpim].include?(type)
          @mentions.replace("<@#{name}>", workspace)
        else
          "##{name}"
        end
      end

      private

      def display_channel_label(result, workspace, options)
        options[:channel_label] || channel_label(result, workspace)
      end

      def workspace_prefix(workspace, options)
        options[:workspace_label] ? "#{@output.cyan("[#{workspace.name}]")} " : ''
      end

      def resolve_user(result, workspace)
        # If we have a username, use it directly
        return result.username if result.username && !result.username.empty?

        # Fallback if user_id is also missing
        return 'Unknown User' unless result.user_id && !result.user_id.to_s.empty?

        # Otherwise resolve the user_id via MentionReplacer
        @mentions.replace("<@#{result.user_id}>", workspace)
      end

      def prepare_text(text, workspace, options)
        @text_processor.process(text, workspace, options)
      end

      def display_files(files)
        files.each do |file|
          @output.puts @output.blue("[Image: #{file[:name]}]")
        end
      end

      def format_time(time)
        time.strftime('%Y-%m-%d %H:%M:%S')
      end
    end
  end
end
