# frozen_string_literal: true

module Slk
  module Support
    # Shared --fetch-attachments behavior for commands that display messages.
    # Expects the including command to provide #debug and #info.
    module AttachmentFetching
      private

      # Download files and attachment images for the given messages.
      # @return [Hash] file_id / "att_<ts>_<idx>" => local path
      def fetch_attachment_files(messages, workspace)
        downloader = Services::FileDownloader.new(
          cache_dir: Support::XdgPaths.new.cache_dir,
          on_debug: ->(msg) { debug(msg) }
        )
        downloader.download_message_files(messages, workspace)
      end

      def downloadable_file_count(messages)
        messages.sum { |m| m.files.size + downloadable_attachment_count(m) }
      end

      def downloadable_attachment_count(message)
        message.attachments.count { |a| a['image_url'] || a['thumb_url'] }
      end

      def print_file_summary(messages)
        file_count = downloadable_file_count(messages)
        return if file_count.zero?

        label = file_count == 1 ? '1 file' : "#{file_count} files"
        puts
        info("#{label} not downloaded. Use --fetch-attachments to download.")
      end
    end
  end
end
