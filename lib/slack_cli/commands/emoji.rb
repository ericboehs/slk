# frozen_string_literal: true

require_relative "../support/inline_images"
require_relative "../support/help_formatter"

module SlackCli
  module Commands
    class Emoji < Base
      include Support::InlineImages

      NETWORK_ERRORS = [
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        URI::InvalidURIError,
        OpenSSL::SSL::SSLError
      ].freeze

      def execute
        result = validate_options
        return result if result

        case positional_args
        in ["status" | "list"] | []
          show_status
        in ["sync-standard"]
          sync_standard
        in ["download", *rest]
          download_emoji(rest.first)
        in ["clear", *rest]
          clear_emoji(rest.first)
        in ["search", query, *_]
          search_emoji(query)
        in ["search"]
          error("Usage: slk emoji search <query>")
          1
        else
          error("Unknown action: #{positional_args.first}")
          1
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def default_options
        super.merge(force: false)
      end

      def handle_option(arg, args, remaining)
        case arg
        when "-f", "--force"
          @options[:force] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new("slk emoji <action> [workspace]")
        help.description("Manage emoji cache.")

        help.section("ACTIONS") do |s|
          s.action("status", "Show emoji cache status")
          s.action("search <query>", "Search emoji by name (all workspaces by default)")
          s.action("sync-standard", "Download standard emoji database (gemoji)")
          s.action("download [ws]", "Download workspace custom emoji")
          s.action("clear [ws]", "Clear emoji cache")
        end

        help.section("OPTIONS") do |s|
          s.option("-w, --workspace", "Limit to specific workspace")
          s.option("-f, --force", "Skip confirmation for clear")
          s.option("-q, --quiet", "Suppress output")
        end

        help.render
      end

      private

      def show_status
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir
        gemoji_path = File.join(paths.cache_dir, "gemoji.json")

        # Show standard emoji status
        if File.exist?(gemoji_path)
          begin
            gemoji = JSON.parse(File.read(gemoji_path))
            puts "Standard emoji database: #{gemoji.size} emojis"
          rescue JSON::ParserError
            puts "Standard emoji database: #{output.yellow("corrupted")}"
            puts "  Run 'slk emoji sync-standard' to re-download"
          end
        else
          puts "Standard emoji database: #{output.yellow("not downloaded")}"
          puts "  Run 'slk emoji sync-standard' to download"
        end

        puts
        puts "Workspace emojis: (#{emoji_dir})"

        target_workspaces.each do |workspace|
          workspace_dir = File.join(emoji_dir, workspace.name)

          if Dir.exist?(workspace_dir)
            files = Dir.glob(File.join(workspace_dir, "*"))
            count = files.count
            size = files.sum { |f| safe_file_size(f) }
            size_str = format_size(size)
            puts "  #{workspace.name}: #{count} emojis (#{size_str})"
          else
            puts "  #{workspace.name}: #{output.yellow("not downloaded")}"
          end
        end

        0
      end

      def search_emoji(query)
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir
        gemoji_path = File.join(paths.cache_dir, "gemoji.json")
        pattern = Regexp.new(Regexp.escape(query), Regexp::IGNORECASE)

        results = []

        # Search standard emoji
        if File.exist?(gemoji_path)
          begin
            gemoji = JSON.parse(File.read(gemoji_path))
            gemoji.each do |name, char|
              results << { name: name, char: char, source: "standard" } if name.match?(pattern)
            end
          rescue JSON::ParserError
            # Skip standard emoji search if cache is corrupted
            debug("Standard emoji cache corrupted, skipping")
          end
        end

        # Search workspace custom emoji (all workspaces by default, or -w to limit)
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces
        workspaces.each do |workspace|
          workspace_dir = File.join(emoji_dir, workspace.name)
          next unless Dir.exist?(workspace_dir)

          Dir.glob(File.join(workspace_dir, "*")).each do |filepath|
            name = File.basename(filepath, ".*")
            results << { name: name, path: filepath, source: workspace.name } if name.match?(pattern)
          end
        end

        if results.empty?
          puts "No emoji matching '#{query}'"
          return 0
        end

        # Group by source
        by_source = results.group_by { |r| r[:source] }

        by_source.each do |source, items|
          puts output.bold(source == "standard" ? "Standard emoji:" : "#{source}:")
          items.sort_by { |r| r[:name] }.each do |item|
            if item[:char]
              puts "#{item[:char]}  :#{item[:name]}:"
            elsif item[:path]
              unless print_inline_image_with_text(item[:path], ":#{item[:name]}:")
                puts ":#{item[:name]}:"
              end
            else
              puts ":#{item[:name]}:"
            end
          end
          puts
        end

        puts "Found #{results.size} emoji matching '#{query}'"
        0
      end

      def print_progress(current, total, downloaded, skipped)
        # Only update every 1% or when downloading (to show new count)
        pct = ((current.to_f / total) * 100).round
        @last_pct ||= -1
        return if pct == @last_pct && downloaded == (@last_downloaded || 0)

        @last_pct = pct
        @last_downloaded = downloaded

        bar_width = 20
        filled = (pct * bar_width / 100).round
        bar = "=" * filled + "-" * (bar_width - filled)
        print "\r  [#{bar}] #{pct}% (#{current}/#{total}) +#{downloaded} new"
        $stdout.flush
      end

      def format_size(bytes)
        if bytes >= 1024 * 1024
          "#{(bytes / (1024.0 * 1024)).round}M"
        elsif bytes >= 1024
          "#{(bytes / 1024.0).round}K"
        else
          "#{bytes}B"
        end
      end

      # Get file size, returning 0 if file doesn't exist or is inaccessible
      def safe_file_size(path)
        File.size(path)
      rescue Errno::ENOENT, Errno::EACCES
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
        rescue JSON::ParserError => e
          error("Failed to parse emoji data: #{e.message}")
          1
        rescue *NETWORK_ERRORS => e
          error("Network error: #{e.message}")
          1
        rescue SystemCallError => e
          error("File system error: #{e.message}")
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

          workspace_dir = File.join(emoji_dir, workspace.name)
          FileUtils.mkdir_p(workspace_dir)

          downloaded = 0
          skipped = 0
          failed = 0
          total = emoji_map.size
          processed = 0

          # Filter to only downloadable (non-alias) emoji
          to_download = emoji_map.reject { |_, url| url.start_with?("alias:") }
          aliases = total - to_download.size

          to_download.each do |name, url|
            processed += 1
            ext = File.extname(URI.parse(url).path)
            ext = ".png" if ext.empty?
            filepath = File.join(workspace_dir, "#{name}#{ext}")

            # Skip if already exists
            if File.exist?(filepath)
              skipped += 1
              print_progress(processed, to_download.size, downloaded, skipped)
              next
            end

            # Download
            begin
              uri = URI.parse(url)
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_PEER
              http.cert_store = OpenSSL::X509::Store.new
              http.cert_store.set_default_paths
              http.open_timeout = 10
              http.read_timeout = 30

              request = Net::HTTP::Get.new(uri)
              response = http.request(request)

              if response.is_a?(Net::HTTPSuccess)
                File.binwrite(filepath, response.body)
                downloaded += 1
              else
                failed += 1
              end
            rescue *NETWORK_ERRORS, SystemCallError => e
              debug("Failed to download emoji #{name}: #{e.message}")
              failed += 1
            end

            print_progress(processed, to_download.size, downloaded, skipped)
          end

          puts "\r#{" " * 60}\r" # Clear progress line
          success("Downloaded #{downloaded} new emoji for #{workspace.name}")
          puts "  Skipped: #{skipped} (already exist), #{aliases} aliases, #{failed} failed" if skipped > 0 || failed > 0
        end

        0
      end

      def clear_emoji(workspace_name)
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        # Gather info about what will be deleted
        to_clear = []
        if workspace_name
          workspace_dir = File.join(emoji_dir, workspace_name)
          if Dir.exist?(workspace_dir)
            to_clear << { name: workspace_name, dir: workspace_dir }
          else
            puts "No emoji cache for #{workspace_name}"
            return 0
          end
        else
          target_workspaces.each do |workspace|
            workspace_dir = File.join(emoji_dir, workspace.name)
            to_clear << { name: workspace.name, dir: workspace_dir } if Dir.exist?(workspace_dir)
          end

          if to_clear.empty?
            puts "No emoji caches to clear"
            return 0
          end
        end

        # Show what will be deleted
        puts "Will delete:"
        total_count = 0
        total_size = 0
        to_clear.each do |entry|
          files = Dir.glob(File.join(entry[:dir], "*"))
          count = files.count
          size = files.sum { |f| safe_file_size(f) }
          total_count += count
          total_size += size
          puts "  #{entry[:name]}: #{count} files (#{format_size(size)})"
        end
        puts "  Total: #{total_count} files (#{format_size(total_size)})"

        # Confirm unless --force
        unless @options[:force]
          print "\nAre you sure? [y/N] "
          response = $stdin.gets&.chomp&.downcase
          unless response == "y" || response == "yes"
            puts "Cancelled"
            return 0
          end
        end

        # Delete
        to_clear.each do |entry|
          FileUtils.rm_rf(entry[:dir])
        end

        success("Cleared #{total_count} emoji files")
        0
      end
    end
  end
end
