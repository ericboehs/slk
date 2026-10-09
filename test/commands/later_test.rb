# frozen_string_literal: true

require 'test_helper'

class LaterCommandTest < Minitest::Test
  # Mock saved API
  class MockSavedApi
    attr_reader :calls

    def initialize
      @calls = []
      @responses = []
    end

    def expect_list(response)
      @responses << response
    end

    def list(filter:, limit:)
      @calls << { filter: filter, limit: limit }
      @responses.shift || { 'ok' => false }
    end
  end

  # Mock conversations API for message fetching
  class MockConversationsApi
    attr_reader :calls

    def initialize
      @calls = []
      @responses = {}
    end

    def stub_history(channel, response)
      @responses[channel] = response
    end

    def history(channel:, limit:, oldest:, latest:)
      @calls << { channel: channel, limit: limit, oldest: oldest, latest: latest }
      @responses[channel] || { 'ok' => true, 'messages' => [] }
    end
  end

  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @saved_api = MockSavedApi.new
    @conversations_api = MockConversationsApi.new
  end

  def test_execute_displays_saved_items
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               {
                                 'item_id' => 'C123',
                                 'item_type' => 'message',
                                 'ts' => '1234567890.123456',
                                 'state' => 'saved'
                               }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    result = command.execute

    assert_equal 0, result
  end

  def test_execute_with_no_items
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/No saved items found/, @io.string)
  end

  def test_execute_with_api_error
    @saved_api.expect_list({ 'ok' => false, 'error' => 'not_allowed' })

    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_match(/Failed to fetch saved items/, @err.string)
  end

  def test_execute_with_completed_filter
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--completed', '--no-content'], runner: runner)
    command.execute

    assert_equal 'completed', @saved_api.calls.first[:filter]
  end

  def test_execute_with_in_progress_filter
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--in-progress', '--no-content'], runner: runner)
    command.execute

    assert_equal 'in_progress', @saved_api.calls.first[:filter]
  end

  def test_execute_with_custom_limit
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['-n', '50', '--no-content'], runner: runner)
    command.execute

    assert_equal 50, @saved_api.calls.first[:limit]
  end

  def test_execute_with_counts_option
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message', 'state' => 'saved' },
                               { 'item_id' => 'C456', 'item_type' => 'message', 'state' => 'saved',
                                 'date_due' => Time.now.to_i - 3600 }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new(['--counts'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/Total: 2/, @io.string)
    assert_match(/Overdue: 1/, @io.string)
  end

  def test_execute_with_json_output
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               {
                                 'item_id' => 'C123',
                                 'item_type' => 'message',
                                 'ts' => '1234567890.123456',
                                 'state' => 'saved',
                                 'date_created' => 1_700_000_000
                               }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new(['--json', '--no-content'], runner: runner)
    result = command.execute

    assert_equal 0, result
    output = JSON.parse(@io.string)
    assert_kind_of Array, output
    assert_equal 1, output.size
    assert_equal 'C123', output[0]['channel_id']
    assert_equal 'saved', output[0]['state']
  end

  def test_help_option
    runner = build_runner
    command = Slk::Commands::Later.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/slk later/, @io.string)
    assert_match(/--limit/, @io.string)
    assert_match(/--completed/, @io.string)
    assert_match(/--counts/, @io.string)
    assert_match(/--no-content/, @io.string)
  end

  def test_default_limit_is_fifteen
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    command.execute

    assert_equal 15, @saved_api.calls.first[:limit]
  end

  def test_default_filter_is_saved
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    command.execute

    assert_equal 'saved', @saved_api.calls.first[:filter]
  end

  def test_execute_handles_api_exception
    runner = build_runner
    # Override saved_api to raise an exception
    error_api = Object.new
    error_api.define_singleton_method(:list) { |**_| raise Slk::ApiError, 'Network timeout' }
    runner.define_singleton_method(:saved_api) { |_| error_api }

    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_match(/Failed to fetch saved items.*Network timeout/, @err.string)
  end

  def test_no_wrap_option_sets_truncate_and_default_width
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-wrap', '--no-content'], runner: runner)

    assert_equal true, command.options[:truncate]
    assert_equal 140, command.options[:width]
  end

  def test_no_wrap_with_explicit_width
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--no-wrap', '--width', '80', '--no-content'], runner: runner)

    assert_equal true, command.options[:truncate]
    assert_equal 80, command.options[:width]
  end

  def test_execute_fetches_message_content_when_not_skipped
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               {
                                 'item_id' => 'C123',
                                 'item_type' => 'message',
                                 'ts' => '1234567890.123456',
                                 'state' => 'saved'
                               }
                             ]
                           })

    @conversations_api.stub_history('C123', {
                                      'ok' => true,
                                      'messages' => [
                                        { 'ts' => '1234567890.123456', 'text' => 'Test message', 'user' => 'U123' }
                                      ]
                                    })

    runner = build_runner_with_cache
    command = Slk::Commands::Later.new([], runner: runner) # No --no-content
    result = command.execute

    assert_equal 0, result
    assert_equal 1, @conversations_api.calls.length
    assert_equal 'C123', @conversations_api.calls.first[:channel]
  end

  def test_workspace_emoji_option_is_parsed
    @saved_api.expect_list({ 'ok' => true, 'saved_items' => [] })

    runner = build_runner
    command = Slk::Commands::Later.new(['--workspace-emoji', '--no-content'], runner: runner)

    assert_equal true, command.options[:workspace_emoji]
  end

  def test_execute_handles_items_without_ts
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message', 'state' => 'saved' }
                             ]
                           })

    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    # Should not attempt to fetch message content when ts is missing
    assert_equal 0, @conversations_api.calls.length
  end

  def test_shows_fetch_failure_summary_when_content_fails
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               {
                                 'item_id' => 'C123',
                                 'item_type' => 'message',
                                 'ts' => '1234567890.123456',
                                 'state' => 'saved'
                               }
                             ]
                           })

    # Return empty messages so fetch_by_ts returns nil
    @conversations_api.stub_history('C123', { 'ok' => true, 'messages' => [] })

    runner = build_runner_with_cache
    command = Slk::Commands::Later.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_match(/Could not load content for 1 item/, @io.string)
  end

  def test_counts_completed_excludes_overdue_section
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C1', 'item_type' => 'message', 'state' => 'completed' }
                             ]
                           })
    runner = build_runner
    command = Slk::Commands::Later.new(['--counts', '--completed'], runner: runner)
    command.execute
    refute_match(/Overdue:/, @io.string)
    assert_match(/Total: 1/, @io.string)
  end

  def test_help_text_contains_all_options
    runner = build_runner
    command = Slk::Commands::Later.new(['--help'], runner: runner)
    command.execute
    %w[--limit --completed --in-progress --counts --no-content
       --workspace-emoji --no-emoji --width --no-wrap --json
       --workspace --verbose --quiet].each do |opt|
      assert_match(/#{Regexp.escape(opt)}/, @io.string)
    end
  end

  def test_workspace_emoji_skipped_in_markdown_mode
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message', 'state' => 'saved' }
                             ]
                           })
    runner = build_runner
    command = Slk::Commands::Later.new(
      ['--workspace-emoji', '--markdown', '--no-content'], runner: runner
    )
    result = command.execute
    assert_equal 0, result
  end

  def test_print_emoji_or_code_with_existing_emoji
    runner = build_runner
    command = Slk::Commands::Later.new(['--no-content'], runner: runner)
    Dir.mktmpdir do |dir|
      emoji_dir = File.join(dir, 'test')
      FileUtils.mkdir_p(emoji_dir)
      emoji_file = File.join(emoji_dir, 'partyparrot.png')
      File.binwrite(emoji_file, "\x89PNG\r\n\u001A\n#{'a' * 80}")
      command.send(:instance_variable_set, :@options, { workspace_emoji: true })

      runner.config.define_singleton_method(:emoji_dir) { dir }

      out = capture_stdout do
        command.send(:print_with_workspace_emoji, ':partyparrot:', mock_workspace('test'))
      end
      assert_kind_of String, out
    end
  end

  def test_find_workspace_emoji_returns_nil_for_empty_name
    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    runner.config.define_singleton_method(:emoji_dir) { nil }
    assert_nil command.send(:find_workspace_emoji, 'test', '')
  end

  def test_find_workspace_emoji_returns_nil_for_missing_dir
    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    runner.config.define_singleton_method(:emoji_dir) { '/nonexistent/path' }
    assert_nil command.send(:find_workspace_emoji, 'test', 'foo')
  end

  def test_json_output_with_content_includes_message
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message',
                                 'ts' => '1234567890.123456', 'state' => 'saved' }
                             ]
                           })
    @conversations_api.stub_history('C123', {
                                      'ok' => true,
                                      'messages' => [{ 'ts' => '1234567890.123456', 'text' => 'Hi', 'user' => 'U1' }]
                                    })
    runner = build_runner_with_cache
    Slk::Commands::Later.new(['--json'], runner: runner).execute
    output = JSON.parse(@io.string)
    assert output[0].key?('message')
  end

  def stub_item_with_file
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message',
                                 'ts' => '1234567890.123456', 'state' => 'saved' }
                             ]
                           })
    @conversations_api.stub_history('C123', {
                                      'ok' => true,
                                      'messages' => [{ 'ts' => '1234567890.123456', 'text' => 'Hi', 'user' => 'U1',
                                                       'files' => [{ 'id' => 'F1', 'name' => 'a.pdf' }] }]
                                    })
  end

  def fake_downloader(paths, calls)
    dl = Object.new
    dl.define_singleton_method(:download_message_files) do |messages, _workspace|
      calls << messages
      paths
    end
    dl
  end

  def test_shows_files_and_summary_without_fetch_attachments
    stub_item_with_file
    Slk::Commands::Later.new([], runner: build_runner_with_cache).execute

    assert_includes @io.string, '[File: a.pdf]'
    assert_includes @io.string, '1 file not downloaded. Use --fetch-attachments to download.'
  end

  def test_fetch_attachments_downloads_and_shows_local_path
    stub_item_with_file
    calls = []
    Slk::Services::FileDownloader.stub(:new, fake_downloader({ 'F1' => '/cache/F1_a.pdf' }, calls)) do
      assert_equal 0, Slk::Commands::Later.new(['--fetch-attachments'], runner: build_runner_with_cache).execute
    end

    assert_equal 1, calls.size
    assert_equal 'F1', calls.first.first.files.first['id']
    assert_includes @io.string, '[File: /cache/F1_a.pdf]'
    refute_includes @io.string, 'not downloaded'
  end

  def test_fetch_attachments_json_includes_file_paths
    stub_item_with_file
    Slk::Services::FileDownloader.stub(:new, fake_downloader({ 'F1' => '/cache/F1_a.pdf' }, [])) do
      Slk::Commands::Later.new(['--json', '--fetch-attachments'], runner: build_runner_with_cache).execute
    end

    output = JSON.parse(@io.string)
    assert_equal({ 'F1' => '/cache/F1_a.pdf' }, output[0]['file_paths'])
  end

  def stub_previews(command, previews)
    command.define_singleton_method(:image_previews_supported?) { true }
    command.define_singleton_method(:print_image_preview) do |path, indent: 2|
      previews << [path, indent]
      true
    end
  end

  def test_fetch_attachments_previews_downloaded_images_under_their_line
    stub_item_with_file
    previews = []
    command = Slk::Commands::Later.new(['--fetch-attachments'], runner: build_runner_with_cache)
    stub_previews(command, previews)
    Slk::Services::FileDownloader.stub(:new, fake_downloader({ 'F1' => '/cache/F1_a.png' }, [])) do
      assert_equal 0, command.execute
    end

    assert_equal [['/cache/F1_a.png', 2]], previews
    assert_includes @io.string, '[File: /cache/F1_a.png]'
  end

  def test_fetch_attachments_skips_preview_for_non_images
    stub_item_with_file
    previews = []
    command = Slk::Commands::Later.new(['--fetch-attachments'], runner: build_runner_with_cache)
    stub_previews(command, previews)
    Slk::Services::FileDownloader.stub(:new, fake_downloader({ 'F1' => '/cache/F1_a.pdf' }, [])) do
      command.execute
    end

    assert_empty previews
    assert_includes @io.string, '[File: /cache/F1_a.pdf]'
  end

  def test_no_previews_without_fetch_attachments
    stub_item_with_file
    previews = []
    command = Slk::Commands::Later.new([], runner: build_runner_with_cache)
    stub_previews(command, previews)
    command.execute

    assert_empty previews
  end

  def test_no_previews_in_markdown_mode
    stub_item_with_file
    previews = []
    command = Slk::Commands::Later.new(['--fetch-attachments', '--markdown'], runner: build_runner_with_cache)
    stub_previews(command, previews)
    Slk::Services::FileDownloader.stub(:new, fake_downloader({ 'F1' => '/cache/F1_a.png' }, [])) do
      command.execute
    end

    assert_empty previews
  end

  def test_no_image_preview_downloads_but_skips_previews
    stub_item_with_file
    previews = []
    calls = []
    command = Slk::Commands::Later.new(%w[--fetch-attachments --no-image-preview], runner: build_runner_with_cache)
    stub_previews(command, previews)
    Slk::Services::FileDownloader.stub(:new, fake_downloader({ 'F1' => '/cache/F1_a.png' }, calls)) do
      assert_equal 0, command.execute
    end

    assert_equal 1, calls.size
    assert_empty previews
    assert_includes @io.string, '[File: /cache/F1_a.png]'
  end

  def test_help_mentions_image_preview_controls
    Slk::Commands::Later.new(['--help'], runner: build_runner).execute

    assert_includes @io.string, '--no-image-preview'
    assert_includes @io.string, 'SLK_IMAGE_PREVIEW=0'
  end

  def test_json_without_fetch_attachments_omits_file_paths
    stub_item_with_file
    Slk::Commands::Later.new(['--json'], runner: build_runner_with_cache).execute

    refute JSON.parse(@io.string)[0].key?('file_paths')
  end

  def test_create_buffer_output_markdown
    runner = build_runner
    command = Slk::Commands::Later.new(['--markdown'], runner: runner)
    buffer = StringIO.new
    out = command.send(:create_buffer_output, buffer)
    assert_instance_of Slk::Formatters::MarkdownOutput, out
  end

  def test_create_buffer_output_regular
    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    buffer = StringIO.new
    out = command.send(:create_buffer_output, buffer)
    assert_instance_of Slk::Formatters::Output, out
  end

  def test_print_emoji_or_code_in_tmux_skips_space
    runner = build_runner
    command = Slk::Commands::Later.new([], runner: runner)
    Dir.mktmpdir do |dir|
      emoji_dir = File.join(dir, 'test')
      FileUtils.mkdir_p(emoji_dir)
      emoji_file = File.join(emoji_dir, 'wave.png')
      File.binwrite(emoji_file, "\x89PNG\r\n\n#{'a' * 80}")
      runner.config.define_singleton_method(:emoji_dir) { dir }
      old_term = ENV.fetch('TERM', nil)
      old_term_program = ENV.fetch('TERM_PROGRAM', nil)
      ENV['TERM'] = 'tmux-256color'
      ENV['TERM_PROGRAM'] = 'iTerm.app'
      out = StringIO.new
      $stdout = out
      command.send(:print_emoji_or_code, 'wave', mock_workspace('test'))
    ensure
      $stdout = STDOUT
      ENV['TERM'] = old_term
      ENV['TERM_PROGRAM'] = old_term_program
    end
  end

  def test_workspace_emoji_path_renders_with_inline_images
    @saved_api.expect_list({
                             'ok' => true,
                             'saved_items' => [
                               { 'item_id' => 'C123', 'item_type' => 'message',
                                 'ts' => '1234567890.123456', 'state' => 'saved' }
                             ]
                           })
    @conversations_api.stub_history('C123', {
                                      'ok' => true,
                                      'messages' => [{ 'ts' => '1234567890.123456', 'text' => 'Hi :wave:',
                                                       'user' => 'U1' }]
                                    })
    runner = build_runner_with_cache
    command = Slk::Commands::Later.new(['--workspace-emoji'], runner: runner)
    command.stub(:inline_images_supported?, true) do
      command.execute
    end
  end

  private

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  def build_runner
    saved_api = @saved_api
    conversations_api = @conversations_api

    token_store = Object.new
    workspace = Slk::Models::Workspace.new(name: 'test', token: 'xoxb-test')

    token_store.define_singleton_method(:workspace) { |_name = nil| workspace }
    token_store.define_singleton_method(:all_workspaces) { [workspace] }
    token_store.define_singleton_method(:workspace_names) { ['test'] }
    token_store.define_singleton_method(:empty?) { false }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:on_warning=) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }

    runner = Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: MockApiClient.new,
      cache_store: cache_store,
      preset_store: preset_store
    )

    # Override the API accessors to return our mocks
    runner.define_singleton_method(:saved_api) { |_workspace_name = nil| saved_api }
    runner.define_singleton_method(:conversations_api) { |_workspace_name = nil| conversations_api }

    runner
  end

  def build_runner_with_cache
    saved_api = @saved_api
    conversations_api = @conversations_api

    token_store = Object.new
    workspace = Slk::Models::Workspace.new(name: 'test', token: 'xoxb-test')

    token_store.define_singleton_method(:workspace) { |_name = nil| workspace }
    token_store.define_singleton_method(:all_workspaces) { [workspace] }
    token_store.define_singleton_method(:workspace_names) { ['test'] }
    token_store.define_singleton_method(:empty?) { false }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { 'test' }
    config.define_singleton_method(:on_warning=) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    # Cache store with user lookup support
    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }
    cache_store.define_singleton_method(:get_user) { |_workspace, _user_id| 'Test User' }
    cache_store.define_singleton_method(:set_user) { |_workspace, _user_id, _name| nil }

    runner = Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: MockApiClient.new,
      cache_store: cache_store,
      preset_store: preset_store
    )

    # Override the API accessors to return our mocks
    runner.define_singleton_method(:saved_api) { |_workspace_name = nil| saved_api }
    runner.define_singleton_method(:conversations_api) { |_workspace_name = nil| conversations_api }

    runner
  end
end
