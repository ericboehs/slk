# frozen_string_literal: true

module SlackCli
  module Services
    # Downloads and caches standard emoji database from gemoji
    class GemojiSync
      GEMOJI_URL = 'https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json'

      NETWORK_ERRORS = [
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        URI::InvalidURIError,
        OpenSSL::SSL::SSLError
      ].freeze

      def initialize(cache_dir:, on_progress: nil)
        @cache_dir = cache_dir
        @on_progress = on_progress
      end

      # Download and cache standard emoji database
      # @return [Hash] Result with :success, :count, :path, or :error
      def sync
        @on_progress&.call('Downloading standard emoji database...')

        response = fetch_gemoji_data
        return response if response[:error]

        emoji_map = parse_and_transform(response[:body])
        return emoji_map if emoji_map[:error]

        save_result = save_to_cache(emoji_map[:data])
        return save_result if save_result[:error]

        { success: true, count: emoji_map[:data].size, path: emoji_json_path }
      end

      def emoji_json_path
        File.join(@cache_dir, 'gemoji.json')
      end

      private

      def fetch_gemoji_data
        http = build_http_client(GEMOJI_URL)
        request = Net::HTTP::Get.new(URI.parse(GEMOJI_URL))
        response = http.request(request)

        return { error: "Failed to download: HTTP #{response.code}" } unless response.is_a?(Net::HTTPSuccess)

        { body: response.body }
      rescue *NETWORK_ERRORS => e
        { error: "Network error: #{e.message}" }
      end

      def build_http_client(url)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = OpenSSL::X509::Store.new
        http.cert_store.set_default_paths
        http
      end

      def parse_and_transform(body)
        emoji_data = JSON.parse(body)
        emoji_map = extract_emoji_aliases(emoji_data)
        { data: emoji_map }
      rescue JSON::ParserError => e
        { error: "Failed to parse emoji data: #{e.message}" }
      end

      def extract_emoji_aliases(emoji_data)
        emoji_map = {}
        emoji_data.each do |emoji|
          char = emoji['emoji']
          next unless char

          (emoji['aliases'] || []).each { |name| emoji_map[name] = char }
        end
        emoji_map
      end

      def save_to_cache(emoji_map)
        FileUtils.mkdir_p(@cache_dir)
        File.write(emoji_json_path, JSON.pretty_generate(emoji_map))
        { success: true }
      rescue SystemCallError => e
        { error: "File system error: #{e.message}" }
      end
    end
  end
end
