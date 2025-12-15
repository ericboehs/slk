# frozen_string_literal: true

module SlackCli
  module Commands
    class Emoji < Base
      def execute
        return show_help if show_help?

        case positional_args
        in ["status" | "list"] | []
          show_status
        in ["sync-standard"]
          sync_standard
        in ["download", *rest]
          download_emoji(rest.first)
        in ["clear", *rest]
          clear_emoji(rest.first)
        else
          error("Unknown action: #{positional_args.first}")
          1
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        <<~HELP
          USAGE: slk emoji <action> [workspace]

          Manage emoji cache.

          ACTIONS:
            status            Show emoji cache status
            sync-standard     Download standard emoji database (gemoji)
            download [ws]     Download workspace custom emoji
            clear [ws]        Clear emoji cache

          OPTIONS:
            -w, --workspace   Specify workspace
            -q, --quiet       Suppress output
        HELP
      end

      private

      def show_status
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        target_workspaces.each do |workspace|
          if target_workspaces.size > 1
            puts output.bold(workspace.name)
          end

          workspace_dir = File.join(emoji_dir, "emoji", workspace.name)

          if Dir.exist?(workspace_dir)
            count = Dir.glob(File.join(workspace_dir, "*")).count
            puts "  Custom emoji: #{count} files"
            puts "  Location: #{workspace_dir}"
          else
            puts "  Custom emoji: #{output.yellow("not downloaded")}"
          end
        end

        0
      end

      def sync_standard
        paths = Support::XdgPaths.new
        cache_dir = paths.cache_dir
        emoji_json_path = File.join(cache_dir, "gemoji.json")

        puts "Downloading standard emoji database..."

        # Download gemoji JSON from GitHub
        gemoji_url = "https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"

        begin
          uri = URI.parse(gemoji_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.cert_store = OpenSSL::X509::Store.new
          http.cert_store.set_default_paths

          request = Net::HTTP::Get.new(uri)
          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            error("Failed to download: HTTP #{response.code}")
            return 1
          end

          # Parse and transform to shortcode -> emoji mapping
          emoji_data = JSON.parse(response.body)
          emoji_map = {}

          emoji_data.each do |emoji|
            char = emoji["emoji"]
            next unless char

            # Add all aliases
            (emoji["aliases"] || []).each do |name|
              emoji_map[name] = char
            end
          end

          # Save to cache
          FileUtils.mkdir_p(cache_dir)
          File.write(emoji_json_path, JSON.pretty_generate(emoji_map))

          success("Downloaded #{emoji_map.size} standard emoji mappings")
          puts "  Location: #{emoji_json_path}"

          0
        rescue StandardError => e
          error("Failed to sync: #{e.message}")
          1
        end
      end

      def download_emoji(workspace_name)
        workspaces = workspace_name ? [runner.workspace(workspace_name)] : target_workspaces
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        workspaces.each do |workspace|
          puts "Fetching emoji list for #{workspace.name}..."

          api = runner.emoji_api(workspace.name)
          emoji_map = api.custom_emoji

          workspace_dir = File.join(emoji_dir, "emoji", workspace.name)
          FileUtils.mkdir_p(workspace_dir)

          downloaded = 0
          skipped = 0

          emoji_map.each do |name, url|
            # Skip aliases (they start with "alias:")
            if url.start_with?("alias:")
              skipped += 1
              next
            end

            ext = File.extname(URI.parse(url).path)
            ext = ".png" if ext.empty?
            filepath = File.join(workspace_dir, "#{name}#{ext}")

            # Skip if already exists
            if File.exist?(filepath)
              skipped += 1
              next
            end

            # Download
            begin
              uri = URI.parse(url)
              response = Net::HTTP.get_response(uri)
              if response.is_a?(Net::HTTPSuccess)
                File.write(filepath, response.body)
                downloaded += 1
                print "."
              end
            rescue StandardError
              # Skip failed downloads
            end
          end

          puts
          success("Downloaded #{downloaded} emoji for #{workspace.name} (#{skipped} skipped)")
        end

        0
      end

      def clear_emoji(workspace_name)
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        if workspace_name
          workspace_dir = File.join(emoji_dir, "emoji", workspace_name)
          FileUtils.rm_rf(workspace_dir)
          success("Cleared emoji cache for #{workspace_name}")
        else
          target_workspaces.each do |workspace|
            workspace_dir = File.join(emoji_dir, "emoji", workspace.name)
            FileUtils.rm_rf(workspace_dir)
          end
          success("Cleared all emoji caches")
        end

        0
      end
    end
  end
end
