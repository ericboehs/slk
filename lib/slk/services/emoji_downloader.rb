# frozen_string_literal: true

module Slk
  module Services
    # Downloads workspace custom emoji to local cache
    class EmojiDownloader
      NETWORK_ERRORS = [
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        URI::InvalidURIError,
        OpenSSL::SSL::SSLError
      ].freeze

      def initialize(emoji_dir:, on_progress: nil, on_debug: nil)
        @emoji_dir = emoji_dir
        @on_progress = on_progress
        @on_debug = on_debug
      end

      # Download custom emoji for a workspace
      # @param workspace_name [String] Name of the workspace
      # @param emoji_map [Hash] Map of emoji name to URL from API
      # @return [Hash] Result with :downloaded, :skipped, :failed, :aliases
      def download(workspace_name, emoji_map)
        workspace_dir = File.join(@emoji_dir, workspace_name)
        FileUtils.mkdir_p(workspace_dir)

        to_download = emoji_map.reject { |_, url| url.start_with?('alias:') }
        stats = initial_stats(emoji_map.size, to_download.size)

        download_all(workspace_dir, to_download, stats)
        stats
      end

      private

      def initial_stats(total_count, downloadable_count)
        { downloaded: 0, skipped: 0, failed: 0, aliases: total_count - downloadable_count, total: downloadable_count }
      end

      def download_all(workspace_dir, to_download, stats)
        to_download.each_with_index do |(name, url), idx|
          result = download_single(workspace_dir, name, url)
          update_stats(stats, result)
          report_progress(idx + 1, stats)
        end
      end

      def update_stats(stats, result)
        stats[result] += 1 if %i[downloaded skipped failed].include?(result)
      end

      def download_single(workspace_dir, name, url)
        ext = File.extname(URI.parse(url).path)
        ext = '.png' if ext.empty?
        filepath = File.join(workspace_dir, "#{name}#{ext}")

        # Skip if already exists
        return :skipped if File.exist?(filepath)

        # Download the emoji
        download_file(url, filepath) ? :downloaded : :failed
      rescue URI::InvalidURIError
        :failed
      end

      def download_file(url, filepath)
        response = fetch_url(url)
        return false unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(filepath, response.body)
        true
      rescue *NETWORK_ERRORS, SystemCallError => e
        @on_debug&.call("Failed to download emoji: #{e.message}")
        false
      end

      def fetch_url(url)
        uri = URI.parse(url)
        http = build_http_client(uri)
        http.request(Net::HTTP::Get.new(uri))
      end

      def build_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = OpenSSL::X509::Store.new
        http.cert_store.set_default_paths
        http.open_timeout = 10
        http.read_timeout = 30
        http
      end

      def report_progress(current, stats)
        @on_progress&.call(current, stats[:total], stats[:downloaded], stats[:skipped])
      end
    end
  end
end
