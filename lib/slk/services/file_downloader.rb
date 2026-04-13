# frozen_string_literal: true

module Slk
  module Services
    # Downloads Slack message files and attachment images to XDG cache dir.
    # Authed files (url_private_download) require workspace headers.
    # Public attachment images (image_url) are fetched without auth.
    # rubocop:disable Metrics/ClassLength
    class FileDownloader
      NETWORK_ERRORS = [
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        URI::InvalidURIError,
        OpenSSL::SSL::SSLError
      ].freeze

      IMAGE_TYPES = %w[png jpg jpeg gif bmp webp svg].freeze
      MAX_REDIRECTS = 3

      def initialize(cache_dir:, on_debug: nil)
        @cache_dir = cache_dir
        @on_debug = on_debug
      end

      # Download all files from a list of messages, returning a hash of
      # file_id => local_path for files and attachment index => local_path for attachments.
      def download_message_files(messages, workspace)
        files_dir = ensure_workspace_dir(workspace.name)
        file_paths = {}

        messages.each do |message|
          download_files(message.files, files_dir, workspace, file_paths)
          download_attachment_images(message.attachments, message.ts, files_dir, file_paths)
        end

        file_paths
      end

      private

      def ensure_workspace_dir(workspace_name)
        dir = File.join(@cache_dir, 'files', workspace_name)
        FileUtils.mkdir_p(dir)
        dir
      end

      def download_files(files, dir, workspace, paths)
        files.each do |file|
          path = download_single_file(file, dir, workspace)
          paths[file['id']] = path if path
        end
      end

      def download_single_file(file, dir, workspace)
        file_id = file['id']
        url = file['url_private_download']
        return unless file_id && url

        name = file['name'] || 'file'
        local_path = File.join(dir, "#{file_id}_#{sanitize_filename(name)}")

        return local_path if cached?(local_path, name)

        download_authed(url, local_path, workspace) ? local_path : nil
      end

      def download_attachment_images(attachments, message_ts, dir, paths)
        attachments.each_with_index do |att, idx|
          path = download_single_attachment(att, message_ts, idx, dir)
          paths["att_#{message_ts}_#{idx}"] = path if path
        end
      end

      def download_single_attachment(att, message_ts, idx, dir)
        url = att['image_url'] || att['thumb_url']
        return unless url && downloadable_image_url?(url)

        local_path = attachment_path(dir, message_ts, idx, url)
        return local_path if cached?(local_path, 'attachment image')

        download_public(url, local_path) ? local_path : nil
      rescue URI::InvalidURIError
        nil
      end

      def attachment_path(dir, message_ts, idx, url)
        ext = File.extname(URI.parse(url).path)
        ext = '.jpg' if ext.empty?
        File.join(dir, "att_#{message_ts}_#{idx}#{ext}")
      end

      def cached?(local_path, label)
        return false unless File.exist?(local_path)

        @on_debug&.call("Skipping #{label} (cached)")
        true
      end

      def downloadable_image_url?(url)
        ext = File.extname(URI.parse(url).path).delete('.').downcase
        IMAGE_TYPES.include?(ext) || url.include?('/giphy') || url.include?('tenor.com')
      rescue URI::InvalidURIError
        false
      end

      def download_authed(url, filepath, workspace)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        apply_workspace_headers(request, workspace)
        write_response(build_http_client(uri).request(request), filepath)
      rescue *NETWORK_ERRORS, SystemCallError => e
        @on_debug&.call("Failed to download file: #{e.message}")
        false
      end

      def apply_workspace_headers(request, workspace)
        request['Authorization'] = workspace.headers['Authorization']
        request['Cookie'] = workspace.headers['Cookie'] if workspace.headers['Cookie']
      end

      def download_public(url, filepath)
        response = fetch_with_redirect(url)
        write_response(response, filepath)
      rescue *NETWORK_ERRORS, SystemCallError => e
        @on_debug&.call("Failed to download attachment image: #{e.message}")
        false
      end

      def fetch_with_redirect(url)
        uri = URI.parse(url)
        MAX_REDIRECTS.times do
          response = build_http_client(uri).request(Net::HTTP::Get.new(uri))
          return response unless response.is_a?(Net::HTTPRedirection) && response['location']

          uri = resolve_redirect(uri, response['location'])
          return response unless uri.host
        end
        # Exhausted redirects — return last response as-is
        build_http_client(uri).request(Net::HTTP::Get.new(uri))
      end

      def resolve_redirect(original_uri, location)
        parsed = URI.parse(location)
        return parsed if parsed.host

        # Relative redirect — resolve against original URI
        URI.parse("#{original_uri.scheme}://#{original_uri.host}:#{original_uri.port}#{location}")
      end

      def write_response(response, filepath) # rubocop:disable Naming/PredicateMethod
        return false unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(filepath, response.body)
        @on_debug&.call("Downloaded #{File.basename(filepath)} (#{response.body.bytesize} bytes)")
        true
      end

      def build_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        if http.use_ssl?
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.cert_store = OpenSSL::X509::Store.new
          http.cert_store.set_default_paths
        end
        http.open_timeout = 10
        http.read_timeout = 30
        http
      end

      def sanitize_filename(name)
        name.gsub(%r{[/\\:*?"<>|]}, '_')
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
