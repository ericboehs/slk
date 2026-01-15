# frozen_string_literal: true

require_relative '../support/inline_images'
require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Downloads and manages workspace custom emoji
    # rubocop:disable Metrics/ClassLength
    class Emoji < Base
      include Support::InlineImages

      def execute
        result = validate_options
        return result if result

        dispatch_action
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      private

      def dispatch_action
        case positional_args
        in ['status' | 'list'] | [] then show_status
        in ['sync-standard'] then sync_standard
        in ['download', *rest] then download_emoji(rest.first)
        in ['clear', *rest] then clear_emoji(rest.first)
        in ['search', query, *_] then search_emoji(query)
        in ['search'] then missing_search_query
        else unknown_action
        end
      end

      def missing_search_query
        error('Usage: slk emoji search <query>')
        1
      end

      def unknown_action
        error("Unknown action: #{positional_args.first}")
        1
      end

      protected

      def default_options
        super.merge(force: false)
      end

      def handle_option(arg, args, remaining)
        case arg
        when '-f', '--force'
          @options[:force] = true
        else
          super
        end
      end

      def help_text
        help = Support::HelpFormatter.new('slk emoji <action> [workspace]')
        help.description('Manage emoji cache.')

        help.section('ACTIONS') do |s|
          s.action('status', 'Show emoji cache status')
          s.action('search <query>', 'Search emoji by name (all workspaces by default)')
          s.action('sync-standard', 'Download standard emoji database (gemoji)')
          s.action('download [ws]', 'Download workspace custom emoji')
          s.action('clear [ws]', 'Clear emoji cache')
        end

        help.section('OPTIONS') do |s|
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('-f, --force', 'Skip confirmation for clear')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def show_status
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        show_standard_emoji_status(paths.cache_dir)
        puts
        show_workspace_emoji_status(emoji_dir)

        0
      end

      def show_standard_emoji_status(cache_dir)
        gemoji_path = File.join(cache_dir, 'gemoji.json')

        if File.exist?(gemoji_path)
          begin
            gemoji = JSON.parse(File.read(gemoji_path))
            puts "Standard emoji database: #{gemoji.size} emojis"
          rescue JSON::ParserError
            puts "Standard emoji database: #{output.yellow('corrupted')}"
            puts "  Run 'slk emoji sync-standard' to re-download"
          end
        else
          puts "Standard emoji database: #{output.yellow('not downloaded')}"
          puts "  Run 'slk emoji sync-standard' to download"
        end
      end

      def show_workspace_emoji_status(emoji_dir)
        puts "Workspace emojis: (#{emoji_dir})"

        target_workspaces.each do |workspace|
          workspace_dir = File.join(emoji_dir, workspace.name)

          if Dir.exist?(workspace_dir)
            files = Dir.glob(File.join(workspace_dir, '*'))
            count = files.count
            size = files.sum { |f| safe_file_size(f) }
            puts "  #{workspace.name}: #{count} emojis (#{format_size(size)})"
          else
            puts "  #{workspace.name}: #{output.yellow('not downloaded')}"
          end
        end
      end

      def search_emoji(query)
        searcher = build_emoji_searcher
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces
        by_source = searcher.search(query, workspaces: workspaces)

        if by_source.empty?
          puts "No emoji matching '#{query}'"
        else
          display_search_results(by_source)
          puts "Found #{by_source.values.flatten.size} emoji matching '#{query}'"
        end
        0
      end

      def build_emoji_searcher
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        Services::EmojiSearcher.new(
          cache_dir: paths.cache_dir,
          emoji_dir: emoji_dir,
          on_debug: ->(msg) { debug(msg) }
        )
      end

      def display_search_results(by_source)
        by_source.each do |source, items|
          puts output.bold(source == 'standard' ? 'Standard emoji:' : "#{source}:")
          items.sort_by { |r| r[:name] }.each do |item|
            display_emoji_item(item)
          end
          puts
        end
      end

      def display_emoji_item(item)
        if item[:char]
          puts "#{item[:char]}  :#{item[:name]}:"
        elsif item[:path]
          puts ":#{item[:name]}:" unless print_inline_image_with_text(item[:path], ":#{item[:name]}:")
        else
          puts ":#{item[:name]}:"
        end
      end

      def print_progress(current, total, downloaded, _skipped)
        # Only update every 1% or when downloading (to show new count)
        pct = ((current.to_f / total) * 100).round
        @last_pct ||= -1
        return if pct == @last_pct && downloaded == (@last_downloaded || 0)

        @last_pct = pct
        @last_downloaded = downloaded

        bar_width = 20
        filled = (pct * bar_width / 100).round
        bar = ('=' * filled) + ('-' * (bar_width - filled))
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

        syncer = Services::GemojiSync.new(
          cache_dir: paths.cache_dir,
          on_progress: ->(msg) { puts msg }
        )

        result = syncer.sync

        if result[:error]
          error(result[:error])
          return 1
        end

        success("Downloaded #{result[:count]} standard emoji mappings")
        puts "  Location: #{result[:path]}"
        0
      end

      def download_emoji(workspace_name)
        workspaces = workspace_name ? [runner.workspace(workspace_name)] : target_workspaces
        downloader = build_emoji_downloader

        workspaces.each { |workspace| download_workspace_emoji(workspace, downloader) }
        0
      end

      def build_emoji_downloader
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        Services::EmojiDownloader.new(
          emoji_dir: emoji_dir,
          on_progress: ->(current, total, downloaded, skipped) { print_progress(current, total, downloaded, skipped) },
          on_debug: ->(msg) { debug(msg) }
        )
      end

      def download_workspace_emoji(workspace, downloader)
        puts "Fetching emoji list for #{workspace.name}..."

        api = runner.emoji_api(workspace.name)
        emoji_map = api.custom_emoji
        stats = downloader.download(workspace.name, emoji_map)

        display_download_results(workspace.name, stats)
      end

      def display_download_results(workspace_name, stats)
        puts "\r#{' ' * 60}\r" # Clear progress line
        success("Downloaded #{stats[:downloaded]} new emoji for #{workspace_name}")
        return unless stats[:skipped].positive? || stats[:failed].positive?

        puts "  Skipped: #{stats[:skipped]} (already exist), #{stats[:aliases]} aliases, #{stats[:failed]} failed"
      end

      def clear_emoji(workspace_name)
        paths = Support::XdgPaths.new
        emoji_dir = config.emoji_dir || paths.cache_dir

        to_clear = gather_dirs_to_clear(emoji_dir, workspace_name)
        return 0 if to_clear.nil?

        stats = display_clear_preview(to_clear)
        return 0 unless confirm_clear?

        perform_clear(to_clear, stats[:total_count])
      end

      def gather_dirs_to_clear(emoji_dir, workspace_name)
        workspace_name ? gather_single_workspace_dir(emoji_dir, workspace_name) : gather_all_workspace_dirs(emoji_dir)
      end

      def gather_single_workspace_dir(emoji_dir, workspace_name)
        workspace_dir = File.join(emoji_dir, workspace_name)
        return [{ name: workspace_name, dir: workspace_dir }] if Dir.exist?(workspace_dir)

        puts "No emoji cache for #{workspace_name}"
        nil
      end

      def gather_all_workspace_dirs(emoji_dir)
        dirs = target_workspaces.filter_map do |workspace|
          workspace_dir = File.join(emoji_dir, workspace.name)
          { name: workspace.name, dir: workspace_dir } if Dir.exist?(workspace_dir)
        end

        return dirs if dirs.any?

        puts 'No emoji caches to clear'
        nil
      end

      def display_clear_preview(to_clear)
        puts 'Will delete:'
        total_count = 0
        total_size = 0

        to_clear.each do |entry|
          files = Dir.glob(File.join(entry[:dir], '*'))
          count = files.count
          size = files.sum { |f| safe_file_size(f) }
          total_count += count
          total_size += size
          puts "  #{entry[:name]}: #{count} files (#{format_size(size)})"
        end

        puts "  Total: #{total_count} files (#{format_size(total_size)})"
        { total_count: total_count, total_size: total_size }
      end

      def confirm_clear?
        return true if @options[:force]

        print "\nAre you sure? [y/N] "
        response = $stdin.gets&.chomp&.downcase
        return true if %w[y yes].include?(response)

        puts 'Cancelled'
        false
      end

      def perform_clear(to_clear, total_count)
        to_clear.each do |entry|
          FileUtils.rm_rf(entry[:dir])
        end

        success("Cleared #{total_count} emoji files")
        0
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
