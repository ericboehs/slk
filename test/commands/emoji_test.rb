# frozen_string_literal: true

require 'test_helper'
require 'fileutils'

class EmojiCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @output = test_output
    @workspace = mock_workspace('test')
    @tmp_dir = Dir.mktmpdir('slk-emoji-test')
    @cache_dir = File.join(@tmp_dir, 'slk')
    FileUtils.mkdir_p(@cache_dir)
    @old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
    @old_localappdata = ENV.fetch('LOCALAPPDATA', nil)
    ENV['XDG_CACHE_HOME'] = @tmp_dir
    ENV['LOCALAPPDATA'] = @tmp_dir
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir) if @tmp_dir && File.exist?(@tmp_dir)
    ENV['XDG_CACHE_HOME'] = @old_cache
    ENV['LOCALAPPDATA'] = @old_localappdata
  end

  def runner
    cache_store = Slk::Services::CacheStore.new(paths: temp_paths)
    config = Object.new
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }
    config.define_singleton_method(:primary_workspace) { 'test' }
    runner = Slk::Runner.new(output: @output, api_client: @mock_client,
                             cache_store: cache_store, config: config)
    workspace = @workspace
    runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    runner.define_singleton_method(:all_workspaces) { [workspace] }
    runner
  end

  def temp_paths
    Slk::Support::XdgPaths.new
  end

  def io_string = @output.instance_variable_get(:@io).string
  def err_string = @output.instance_variable_get(:@err).string

  def execute_with_args(args)
    Slk::Commands::Emoji.new(args, runner: runner).execute
  end

  def write_gemoji(data = { 'smile' => "\u{1F604}" })
    File.write(File.join(@cache_dir, 'gemoji.json'), JSON.generate(data))
  end

  def write_workspace_emoji(name = 'partyparrot', ext = 'gif')
    ws_dir = File.join(@cache_dir, 'test')
    FileUtils.mkdir_p(ws_dir)
    File.write(File.join(ws_dir, "#{name}.#{ext}"), 'fake')
  end

  def test_help
    assert_equal 0, execute_with_args(['--help'])
    assert_includes io_string, 'slk emoji'
  end

  def test_status_no_gemoji_no_workspace
    assert_equal 0, execute_with_args(['status'])
    assert_includes io_string, 'not downloaded'
  end

  def test_status_with_gemoji
    write_gemoji
    assert_equal 0, execute_with_args(['status'])
    assert_includes io_string, '1 emojis'
  end

  def test_status_corrupted_gemoji
    File.write(File.join(@cache_dir, 'gemoji.json'), '{ corrupt')
    assert_equal 0, execute_with_args(['status'])
    assert_includes io_string, 'corrupted'
  end

  def test_status_default_action
    assert_equal 0, execute_with_args([])
  end

  def test_status_list_alias
    assert_equal 0, execute_with_args(['list'])
  end

  def test_status_with_workspace_emoji
    write_workspace_emoji
    assert_equal 0, execute_with_args(['status'])
    assert_includes io_string, 'test'
  end

  def test_search_no_results
    assert_equal 0, execute_with_args(%w[search xyznotfound])
    assert_includes io_string, 'No emoji matching'
  end

  def test_search_finds_standard
    write_gemoji('smile' => "\u{1F604}")
    assert_equal 0, execute_with_args(%w[search smile])
    assert_includes io_string, 'smile'
  end

  def test_search_finds_workspace
    write_workspace_emoji('partyparrot', 'gif')
    assert_equal 0, execute_with_args(%w[search party])
    assert_includes io_string, 'partyparrot'
  end

  def test_search_missing_query
    assert_equal 1, execute_with_args(['search'])
    assert_includes err_string, 'slk emoji search'
  end

  def test_unknown_action
    assert_equal 1, execute_with_args(['foobar'])
    assert_includes err_string, 'Unknown action'
  end

  def test_sync_standard_success
    fake_path = File.join(@tmp_dir, 'gemoji.json')
    fake = Object.new
    fake.define_singleton_method(:sync) { { count: 1500, path: fake_path } }
    Slk::Services::GemojiSync.stub(:new, fake) do
      assert_equal 0, execute_with_args(['sync-standard'])
    end
    assert_includes io_string, 'Downloaded 1500'
  end

  def test_sync_standard_error
    fake = Object.new
    fake.define_singleton_method(:sync) { { error: 'fetch failed' } }
    Slk::Services::GemojiSync.stub(:new, fake) do
      assert_equal 1, execute_with_args(['sync-standard'])
    end
    assert_includes err_string, 'fetch failed'
  end

  def test_download_emoji
    fake_api = Object.new
    fake_api.define_singleton_method(:custom_emoji) { { 'foo' => 'http://x' } }
    runner_obj = runner
    runner_obj.define_singleton_method(:emoji_api) { |_| fake_api }
    fake_dl = Object.new
    fake_dl.define_singleton_method(:download) do |_, _|
      { downloaded: 1, skipped: 0, aliases: 0, failed: 0 }
    end
    Slk::Services::EmojiDownloader.stub(:new, fake_dl) do
      assert_equal 0, Slk::Commands::Emoji.new(['download'], runner: runner_obj).execute
    end
  end

  def test_download_emoji_with_workspace
    fake_api = Object.new
    fake_api.define_singleton_method(:custom_emoji) { {} }
    runner_obj = runner
    runner_obj.define_singleton_method(:emoji_api) { |_| fake_api }
    fake_dl = Object.new
    fake_dl.define_singleton_method(:download) do |_, _|
      { downloaded: 0, skipped: 5, aliases: 0, failed: 1 }
    end
    Slk::Services::EmojiDownloader.stub(:new, fake_dl) do
      assert_equal 0, Slk::Commands::Emoji.new(%w[download test], runner: runner_obj).execute
    end
    assert_includes io_string, 'Skipped: 5'
  end

  def test_clear_no_cache
    assert_equal 0, execute_with_args(['clear'])
    assert_includes io_string, 'No emoji caches'
  end

  def test_clear_specific_workspace_no_cache
    assert_equal 0, execute_with_args(%w[clear missing])
    assert_includes io_string, 'No emoji cache'
  end

  def test_clear_with_force
    write_workspace_emoji
    assert_equal 0, execute_with_args(['clear', '--force'])
    assert_includes io_string, 'Cleared'
  end

  def test_clear_specific_with_force
    write_workspace_emoji
    assert_equal 0, execute_with_args(['clear', 'test', '--force'])
    assert_includes io_string, 'Cleared'
  end

  def test_clear_cancelled
    write_workspace_emoji
    fake_stdin = StringIO.new("n\n")
    $stdin = fake_stdin
    assert_equal 0, execute_with_args(['clear'])
    assert_includes io_string, 'Cancelled'
  ensure
    $stdin = STDIN
  end

  def test_clear_confirmed
    write_workspace_emoji
    fake_stdin = StringIO.new("y\n")
    $stdin = fake_stdin
    assert_equal 0, execute_with_args(['clear'])
    assert_includes io_string, 'Cleared'
  ensure
    $stdin = STDIN
  end

  def test_format_size_branches
    cmd = Slk::Commands::Emoji.new([], runner: runner)
    assert_equal '500B', cmd.send(:format_size, 500)
    assert_equal '2K', cmd.send(:format_size, 2048)
    assert_equal '2M', cmd.send(:format_size, 2 * 1024 * 1024)
  end

  def test_safe_file_size
    cmd = Slk::Commands::Emoji.new([], runner: runner)
    assert_equal 0, cmd.send(:safe_file_size, '/nonexistent/path/xyz')
  end

  def test_search_with_workspace_option
    write_workspace_emoji('foobar', 'gif')
    assert_equal 0, execute_with_args(['search', 'foobar', '-w', 'test'])
    assert_includes io_string, 'foobar'
  end

  def test_print_progress_branches
    cmd = Slk::Commands::Emoji.new([], runner: runner)
    cmd.send(:print_progress, 1, 100, 1, 0)
    cmd.send(:print_progress, 1, 100, 1, 0) # Same -> early return
    cmd.send(:print_progress, 50, 100, 5, 0)
  end

  def test_clear_with_user_input_no
    write_workspace_emoji
    fake_stdin = StringIO.new("\n")
    $stdin = fake_stdin
    assert_equal 0, execute_with_args(['clear'])
    assert_includes io_string, 'Cancelled'
  ensure
    $stdin = STDIN
  end

  def test_api_error_handling
    @mock_client.define_singleton_method(:post) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'auth_error'
    end
    runner_obj = runner
    runner_obj.define_singleton_method(:emoji_api) do |_|
      api = Object.new
      api.define_singleton_method(:custom_emoji) { raise Slk::ApiError, 'auth_error' }
      api
    end
    assert_equal 1, Slk::Commands::Emoji.new(['download'], runner: runner_obj).execute
    assert_includes err_string, 'Failed'
  end
end
