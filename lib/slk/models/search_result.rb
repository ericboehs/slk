# frozen_string_literal: true

module Slk
  module Models
    # Value object for search.messages API results
    # Search results include channel info inline, unlike regular messages
    SearchResult = Data.define(
      :ts,
      :user_id,
      :username,
      :text,
      :channel_id,
      :channel_name,
      :channel_type,
      :thread_ts,
      :permalink,
      :files
    ) do
      def self.from_api(match)
        channel = match['channel'] || {}
        new(**build_attributes(match, channel))
      end

      # rubocop:disable Metrics/MethodLength
      def self.build_attributes(match, channel)
        {
          ts: match['ts'],
          user_id: match['user'] || match['username'],
          username: match['username'],
          text: match['text'] || '',
          channel_id: channel['id'],
          channel_name: channel['name'],
          channel_type: determine_channel_type(channel),
          thread_ts: extract_thread_ts(match),
          permalink: match['permalink'],
          files: extract_files(match)
        }
      end

      def self.extract_files(match)
        files = extract_uploaded_files(match)
        files += extract_attachments(match)
        files
      end

      def self.extract_uploaded_files(match)
        return [] unless match['files']

        match['files'].map { |f| { name: f['name'], type: f['filetype'] } }
      end

      def self.extract_attachments(match)
        return [] unless match['attachments']

        match['attachments'].flat_map { |a| extract_attachment_images(a) }
      end

      def self.extract_attachment_images(attachment)
        unless attachment['blocks']
          fallback = attachment['fallback']
          return [] unless fallback

          return [{ name: fallback, type: 'attachment' }]
        end

        attachment['blocks'].filter_map do |block|
          next unless block['type'] == 'image'

          { name: block.dig('title', 'text') || 'Image', type: 'attachment' }
        end
      end
      # rubocop:enable Metrics/MethodLength

      def self.determine_channel_type(channel)
        return 'im' if channel['is_im']
        return 'mpim' if channel['is_mpim']

        'channel'
      end

      def self.extract_thread_ts(match)
        return nil unless match['permalink']

        # Extract thread_ts from permalink URL if present
        uri = URI.parse(match['permalink'])
        params = URI.decode_www_form(uri.query || '')
        params.find { |k, _| k == 'thread_ts' }&.last
      rescue URI::InvalidURIError => e
        # Log for debugging - malformed permalinks from API should be rare
        warn "Invalid permalink URI: #{match['permalink']}: #{e.message}" if ENV['DEBUG']
        nil
      end

      def timestamp
        Time.at(ts.to_f)
      end

      def thread?
        !thread_ts.nil?
      end

      def dm?
        %w[im mpim].include?(channel_type)
      end

      def display_channel
        if dm?
          "@#{channel_name}"
        else
          "##{channel_name}"
        end
      end
    end
  end
end
