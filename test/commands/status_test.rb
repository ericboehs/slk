# frozen_string_literal: true

require 'test_helper'

class StatusCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def create_runner(workspaces: nil)
    # Create a mock token store
    token_store = Object.new
    workspace_list = workspaces || [mock_workspace('test')]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end

    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { workspace_list.first&.name }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store
    )
  end

  def test_get_status_displays_status
    @mock_client.stub('users.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'status_text' => 'Working',
                          'status_emoji' => ':computer:',
                          'status_expiration' => 0
                        }
                      })

    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Working'
    assert_includes @io.string, ':computer:'
  end

  def test_get_status_shows_no_status_message
    @mock_client.stub('users.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'status_text' => '',
                          'status_emoji' => '',
                          'status_expiration' => 0
                        }
                      })

    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, '(no status set)'
  end

  def test_set_status_calls_api
    @mock_client.stub('users.profile.set', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Working from home', ':house:'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert call, 'Expected users.profile.set to be called'
    assert_equal 'Working from home', call[:params][:profile][:status_text]
    assert_equal ':house:', call[:params][:profile][:status_emoji]
  end

  def test_set_status_with_duration
    @mock_client.stub('users.profile.set', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Meeting', ':calendar:', '1h'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert call
    # Should have expiration set
    assert call[:params][:profile][:status_expiration].positive?
  end

  def test_clear_status
    @mock_client.stub('users.profile.set', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['clear'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert call
    assert_equal '', call[:params][:profile][:status_text]
    assert_equal '', call[:params][:profile][:status_emoji]
  end

  def test_help_option
    runner = create_runner
    command = Slk::Commands::Status.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk status'
    assert_includes @io.string, 'OPTIONS'
  end

  def test_api_error_returns_one
    # Make the API raise an error by redefining get
    api_client = Object.new
    api_client.define_singleton_method(:get) do |_workspace, _method, _params = {}|
      raise Slk::ApiError, 'channel_not_found'
    end
    api_client.define_singleton_method(:post) do |_workspace, _method, _params = {}|
      raise Slk::ApiError, 'channel_not_found'
    end

    runner = create_runner
    # Replace the api_client
    runner.instance_variable_set(:@api_client, api_client)

    command = Slk::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Failed'
  end

  def test_set_status_with_presence_option
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Working', ':computer:', '-p', 'away'], runner: runner)
    result = command.execute

    assert_equal 0, result

    presence_call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert presence_call
    assert_equal 'away', presence_call[:params][:presence]
  end

  def test_set_status_with_dnd_option
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('dnd.setSnooze', { 'ok' => true, 'snooze_enabled' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Focus', ':headphones:', '-d', '2h'], runner: runner)
    result = command.execute

    assert_equal 0, result

    dnd_call = @mock_client.calls.find { |c| c[:method] == 'dnd.setSnooze' }
    assert dnd_call
    assert_equal 120, dnd_call[:params][:num_minutes]
  end

  def test_set_status_with_dnd_off
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('dnd.endSnooze', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Working', ':computer:', '-d', 'off'], runner: runner)
    result = command.execute

    assert_equal 0, result

    dnd_call = @mock_client.calls.find { |c| c[:method] == 'dnd.endSnooze' }
    assert dnd_call
  end

  def test_unknown_option_returns_error
    runner = create_runner
    command = Slk::Commands::Status.new(['--invalid-option'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown option'
    assert_includes @err.string, '--invalid-option'
  end

  def test_known_options_are_accepted
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    # Test valid options -p and -d
    command = Slk::Commands::Status.new(['Working', '-p', 'away'], runner: runner)
    result = command.execute

    assert_equal 0, result
    refute_includes @err.string, 'Unknown option'
  end

  def test_set_status_default_emoji_when_none_provided
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner
    Slk::Commands::Status.new(['Lunch'], runner: runner).execute
    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert_equal ':speech_balloon:', call[:params][:profile][:status_emoji]
  end

  def test_get_status_with_explicit_workspace_option
    @mock_client.stub('users.profile.get', { 'ok' => true,
                                             'profile' => { 'status_text' => '', 'status_emoji' => '' } })
    runner = create_runner(workspaces: [mock_workspace('one'), mock_workspace('two')])
    Slk::Commands::Status.new(['-w', 'one'], runner: runner).execute
    refute_includes @io.string, 'two'
  end

  def test_get_status_multi_workspace_shows_workspace_label
    @mock_client.stub('users.profile.get', { 'ok' => true,
                                             'profile' => { 'status_text' => 'Hi',
                                                            'status_emoji' => ':wave:' } })
    runner = create_runner(workspaces: [mock_workspace('one'), mock_workspace('two')])
    Slk::Commands::Status.new([], runner: runner).execute
    assert_includes @io.string, 'one'
    assert_includes @io.string, 'two'
  end

  def test_set_status_presence_active_translates_to_auto
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })
    runner = create_runner
    Slk::Commands::Status.new(['Working', '-p', 'active'], runner: runner).execute
    presence_call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert_equal 'auto', presence_call[:params][:presence]
  end

  def test_show_all_workspaces_hint_with_multiple
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner(workspaces: [mock_workspace('a'), mock_workspace('b')])
    Slk::Commands::Status.new(['Hello'], runner: runner).execute
    assert_match(/--all/, @io.string)
  end

  def test_show_all_workspaces_hint_skipped_with_workspace
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner(workspaces: [mock_workspace('a'), mock_workspace('b')])
    Slk::Commands::Status.new(['Hello', '-w', 'a'], runner: runner).execute
    refute_match(/Tip/, @io.string)
  end

  def test_clear_with_workspace_filter
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner(workspaces: [mock_workspace('a'), mock_workspace('b')])
    Slk::Commands::Status.new(['clear', '-w', 'a'], runner: runner).execute
    # Successfully cleared
    assert_includes @io.string, 'cleared'
  end

  def test_display_status_with_inline_image_when_supported
    Dir.mktmpdir do |dir|
      emoji_dir = File.join(dir, 'test')
      FileUtils.mkdir_p(emoji_dir)
      File.binwrite(File.join(emoji_dir, 'computer.png'), "\x89PNG\r\n\n#{'a' * 80}")

      @mock_client.stub('users.profile.get', {
                          'ok' => true,
                          'profile' => {
                            'status_text' => 'Coding', 'status_emoji' => ':computer:',
                            'status_expiration' => Time.now.to_i + 3600
                          }
                        })
      runner = create_runner
      runner.config.define_singleton_method(:emoji_dir) { dir }
      command = Slk::Commands::Status.new([], runner: runner)
      command.stub(:inline_images_supported?, true) do
        command.stub(:print_inline_image_with_text, ->(_p, _t, **_o) { true }) do
          command.execute
        end
      end
    end
  end

  def test_find_workspace_emoji_returns_nil_for_empty_emoji
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    assert_nil command.send(:find_workspace_emoji, 'test', '')
  end

  def test_find_workspace_emoji_returns_nil_when_dir_missing
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    runner.config.define_singleton_method(:emoji_dir) { '/no/such/path' }
    assert_nil command.send(:find_workspace_emoji, 'test', 'foo')
  end

  def test_print_status_with_image_text_only
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    captured = []
    command.stub(:print_inline_image_with_text, ->(_p, t, **_o) { captured << t }) do
      status = Slk::Models::Status.new(text: '', emoji: ':a:', expiration: 0)
      command.send(:print_status_with_image, '/tmp/img.png', status)
    end
    refute_includes captured.first, '('
  end

  def test_print_status_with_image_text_and_remaining
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    captured = []
    command.stub(:print_inline_image_with_text, ->(_p, t, **_o) { captured << t }) do
      status = Slk::Models::Status.new(text: 'Working', emoji: ':a:', expiration: Time.now.to_i + 3600)
      command.send(:print_status_with_image, '/tmp/img.png', status)
    end
    assert_match(/Working/, captured.first)
    assert_match(/\(/, captured.first)
  end
end
