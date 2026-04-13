# frozen_string_literal: true

module Slk
  module Formatters
    # Formats Slack message attachments for terminal display
    class AttachmentFormatter
      def initialize(output:, text_processor:)
        @output = output
        @text_processor = text_processor
      end

      def format(attachments, lines, options, message_ts: nil)
        return if attachments.empty?
        return if options[:no_attachments]

        attachments.each_with_index do |att, idx|
          format_attachment(att, lines, options, message_ts: message_ts, index: idx)
        end
      end

      private

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def format_attachment(attachment, lines, options, message_ts: nil, index: 0)
        att_text = attachment['text'] || attachment['fallback']
        image_url = attachment['image_url'] || attachment['thumb_url']
        block_images = extract_block_images(attachment)

        return unless att_text || image_url || block_images.any?

        lines << ''
        format_author(attachment, lines)
        format_text(att_text, lines, options) if att_text && block_images.empty?
        format_image(attachment, lines, options, message_ts: message_ts, index: index) if image_url
        block_images.each { |img| lines << "> [Image: #{img}]" }
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def extract_block_images(attachment)
        return [] unless attachment['blocks']

        attachment['blocks'].filter_map do |block|
          next unless block['type'] == 'image'

          block.dig('title', 'text') || 'Image'
        end
      end

      def format_author(attachment, lines)
        author = attachment['author_name'] || attachment['author_subname']
        lines << "> #{@output.bold(author)}:" if author
      end

      def format_text(att_text, lines, options)
        processed_text = @text_processor.call(att_text)
        processed_text = wrap_text(processed_text, options[:width])

        processed_text.each_line do |line|
          lines << "> #{line.chomp}"
        end
      end

      def wrap_text(text, width)
        return text unless width && width > 2

        Support::TextWrapper.wrap(text, width - 2, width - 2)
      end

      def format_image(attachment, lines, options, message_ts: nil, index: 0)
        local_path = lookup_attachment_path(options, message_ts, index)
        if local_path
          lines << "> [Image: #{local_path}]"
        else
          image_url = attachment['image_url'] || attachment['thumb_url']
          filename = attachment['title'] || extract_filename(image_url)
          lines << "> [Image: #{filename}]"
        end
      end

      def lookup_attachment_path(options, message_ts, index)
        return nil unless message_ts

        key = "att_#{message_ts}_#{index}"
        options.dig(:file_paths, key)
      end

      def extract_filename(url)
        File.basename(URI.parse(url).path)
      rescue URI::InvalidURIError
        'image'
      end
    end
  end
end
