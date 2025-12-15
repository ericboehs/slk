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
          remaining << arg
        end
      end

      def help_text
        <<~HELP
          USAGE: slk emoji <action> [workspace]

          Manage emoji cache.

          ACTIONS:
            status            Show emoji cache status
            search <query>    Search emoji by name
            sync-standard     Download standard emoji database (gemoji)
            download [ws]     Download workspace custom emoji
            clear [ws]        Clear emoji cache

          OPTIONS:
            -w, --workspace   Specify workspace
            -f, --force       Skip confirmation for clear
            -q, --quiet       Suppress output
        HELP
      end

      private

      def show_status
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir
        gemoji_path = File.join(paths.cache_dir, "gemoji.json")

        # Show standard emoji status
        if File.exist?(gemoji_path)
          gemoji = JSON.parse(File.read(gemoji_path))
          puts "Standard emoji database: #{gemoji.size} emojis"
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
            size = files.sum { |f| File.size(f) rescue 0 }
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
          gemoji = JSON.parse(File.read(gemoji_path))
          gemoji.each do |name, char|
            results << { name: name, char: char, source: "standard" } if name.match?(pattern)
          end
        end

        # Search workspace custom emoji
        target_workspaces.each do |workspace|
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
              puts "  #{item[:char]}  :#{item[:name]}:"
            elsif item[:path] && inline_images_supported?
              print "  "
              print_inline_image(item[:path])
              puts "  :#{item[:name]}:"
            else
              puts "  :#{item[:name]}:"
            end
          end
          puts
        end

        puts "Found #{results.size} emoji matching '#{query}'"
        0
      end

      def inline_images_supported?
        # iTerm2, WezTerm, Mintty support inline images
        # LC_TERMINAL persists through tmux/ssh
        ENV["TERM_PROGRAM"] == "iTerm.app" ||
          ENV["TERM_PROGRAM"] == "WezTerm" ||
          ENV["LC_TERMINAL"] == "iTerm2" ||
          ENV["LC_TERMINAL"] == "WezTerm" ||
          ENV["TERM"] == "mintty"
      end

      def in_tmux?
        ENV["TMUX"] && !ENV["TMUX"].empty?
      end

      def print_inline_image(path)
        return unless File.exist?(path)

        data = File.binread(path)
        encoded = [data].pack("m0") # Base64 encode

        # iTerm2 inline image protocol
        osc = "\e]1337;File=inline=1;height=1;preserveAspectRatio=1:#{encoded}\a"

        if in_tmux?
          # Wrap for tmux passthrough (double escapes, use \e\\ terminator)
          print "\ePtmux;\e#{osc.gsub("\a", "\e\a")}\e\\"
        else
          print osc
        end
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
            rescue StandardError => e
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
          size = files.sum { |f| File.size(f) rescue 0 }
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
