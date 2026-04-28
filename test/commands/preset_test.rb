# frozen_string_literal: true

require 'test_helper'

class PresetCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @preset_store = MockPresetStore.new
  end

  def create_runner(workspaces: nil, preset_store: nil)
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
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:[]) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }

    ps = preset_store || @preset_store
    ps.define_singleton_method(:on_warning=) { |_| nil } unless ps.respond_to?(:on_warning=)

    Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: ps,
      cache_store: cache_store
    )
  end

  def test_list_presets_empty
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No presets'
  end

  def test_list_presets_shows_presets
    @preset_store.presets = {
      'meeting' => { 'text' => 'In a meeting', 'emoji' => ':calendar:', 'duration' => '1h', 'presence' => '',
                     'dnd' => '' }
    }
    runner = create_runner
    command = Slk::Commands::Preset.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'meeting'
    assert_includes @io.string, 'In a meeting'
  end

  def test_list_presets_default_action
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No presets'
  end

  def test_ls_alias
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(['ls'], runner: runner)
    result = command.execute

    assert_equal 0, result
  end

  def test_apply_preset
    @preset_store.presets = {
      'lunch' => { 'text' => 'Lunch', 'emoji' => ':fork:', 'duration' => '1h', 'presence' => 'away', 'dnd' => '' }
    }
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Preset.new(['lunch'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, "Applied preset 'lunch'"
  end

  def test_apply_preset_not_found
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(['nonexistent'], runner: runner)
    command.execute

    assert_includes @err.string, 'not found'
  end

  def test_delete_preset
    @preset_store.presets = { 'lunch' => {} }
    runner = create_runner
    command = Slk::Commands::Preset.new(%w[delete lunch], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'deleted'
  end

  def test_delete_preset_rm_alias
    @preset_store.presets = { 'lunch' => {} }
    runner = create_runner
    command = Slk::Commands::Preset.new(%w[rm lunch], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'deleted'
  end

  def test_delete_preset_not_found
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(%w[delete nonexistent], runner: runner)
    command.execute

    assert_includes @err.string, 'not found'
  end

  def test_help_option
    runner = create_runner
    command = Slk::Commands::Preset.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk preset'
    assert_includes @io.string, 'list'
    assert_includes @io.string, 'add'
  end

  def test_list_with_full_preset_options
    @preset_store.presets = {
      'meeting' => { 'text' => 'In meeting', 'emoji' => ':calendar:', 'duration' => '1h',
                     'presence' => 'away', 'dnd' => '1h' }
    }
    runner = create_runner
    command = Slk::Commands::Preset.new(['list'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'Duration: 1h'
    assert_includes @io.string, 'Presence: away'
    assert_includes @io.string, 'DND: 1h'
  end

  def test_add_preset_interactive
    fake_input = StringIO.new("focus\nFocusing\n:headphones:\n2h\n\n\n")
    $stdin = fake_input
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(['add'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'created'
  ensure
    $stdin = STDIN
  end

  def test_add_preset_empty_name
    fake_input = StringIO.new("\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Preset.new(['add'], runner: runner)
    command.execute
    assert_includes @err.string, 'Name is required'
  ensure
    $stdin = STDIN
  end

  def test_edit_preset
    @preset_store.presets = {
      'lunch' => { 'text' => 'Lunch', 'emoji' => ':fork:', 'duration' => '1h',
                   'presence' => '', 'dnd' => '' }
    }
    fake_input = StringIO.new("\n\n\n\n\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Preset.new(%w[edit lunch], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'updated'
  ensure
    $stdin = STDIN
  end

  def test_edit_preset_not_found
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(%w[edit unknown], runner: runner)
    command.execute
    assert_includes @err.string, 'not found'
  end

  def test_apply_preset_with_dnd
    @preset_store.presets = {
      'focus' => { 'text' => 'Focus', 'emoji' => ':headphones:', 'duration' => '1h',
                   'presence' => '', 'dnd' => '1h' }
    }
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('dnd.setSnooze', { 'ok' => true })
    runner = create_runner
    command = Slk::Commands::Preset.new(['focus'], runner: runner)
    assert_equal 0, command.execute
  end

  def test_apply_preset_with_dnd_off
    @preset_store.presets = {
      'available' => { 'text' => '', 'emoji' => '', 'duration' => '0',
                       'presence' => '', 'dnd' => 'off' }
    }
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('dnd.endSnooze', { 'ok' => true })
    runner = create_runner
    command = Slk::Commands::Preset.new(['available'], runner: runner)
    assert_equal 0, command.execute
  end

  def test_apply_preset_clears_status
    @preset_store.presets = {
      'clear' => { 'text' => '', 'emoji' => '', 'duration' => '0',
                   'presence' => '', 'dnd' => '' }
    }
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner
    command = Slk::Commands::Preset.new(['clear'], runner: runner)
    assert_equal 0, command.execute
  end

  def test_apply_preset_api_error
    @preset_store.presets = {
      'foo' => { 'text' => 'F', 'emoji' => ':x:', 'duration' => '1h',
                 'presence' => '', 'dnd' => '' }
    }
    runner = create_runner
    @mock_client.define_singleton_method(:post) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'boom'
    end
    command = Slk::Commands::Preset.new(['foo'], runner: runner)
    assert_equal 1, command.execute
    assert_includes @err.string, 'Failed to apply'
  end

  def test_list_finds_workspace_emoji_path
    @preset_store.presets = {
      'meeting' => { 'text' => 'Meeting', 'emoji' => ':calendar:', 'duration' => '0',
                     'presence' => '', 'dnd' => '' }
    }
    Dir.mktmpdir('slk-preset-emoji') do |dir|
      ws_dir = File.join(dir, 'slk', 'test')
      FileUtils.mkdir_p(ws_dir)
      File.write(File.join(ws_dir, 'calendar.png'), 'fake')
      old = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['XDG_CACHE_HOME'] = dir
      runner = create_runner
      assert_equal 0, Slk::Commands::Preset.new(['list'], runner: runner).execute
      ENV['XDG_CACHE_HOME'] = old
    end
  end

  def test_list_preset_with_no_status
    @preset_store.presets = {
      'empty' => { 'text' => '', 'emoji' => '', 'duration' => '0', 'presence' => '', 'dnd' => '' }
    }
    runner = create_runner
    assert_equal 0, Slk::Commands::Preset.new(['list'], runner: runner).execute
    assert_includes @io.string, 'empty'
  end

  def test_unknown_action_falls_through_to_apply
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(%w[nothere extra], runner: runner)
    command.execute
    assert_includes @err.string, 'not found'
  end

  def test_list_alias_ls
    @preset_store.presets = {}
    runner = create_runner
    command = Slk::Commands::Preset.new(['ls'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'No presets'
  end

  def test_find_workspace_emoji_any_returns_nil_for_empty_name
    runner = create_runner
    command = Slk::Commands::Preset.new(['list'], runner: runner)
    assert_nil command.send(:find_workspace_emoji_any, '')
  end

  def test_find_workspace_emoji_any_returns_path_when_found
    Dir.mktmpdir do |dir|
      ws_dir = File.join(dir, 'test')
      FileUtils.mkdir_p(ws_dir)
      emoji_file = File.join(ws_dir, 'foo.png')
      File.write(emoji_file, 'data')

      runner = create_runner
      runner.config.define_singleton_method(:emoji_dir) { dir }
      command = Slk::Commands::Preset.new(['list'], runner: runner)
      result = command.send(:find_workspace_emoji_any, 'foo')
      assert_equal emoji_file, result
    end
  end

  def test_add_preset_with_empty_name_returns_error
    runner = create_runner
    command = Slk::Commands::Preset.new(['add'], runner: runner)
    $stdin = StringIO.new("\n")
    result = command.execute
    assert_equal 1, result
    assert_includes @err.string, 'Name is required'
  ensure
    $stdin = STDIN
  end

  def test_add_preset_with_nil_name_returns_error
    runner = create_runner
    command = Slk::Commands::Preset.new(['add'], runner: runner)
    $stdin = StringIO.new('') # eof - gets returns nil
    result = command.execute
    assert_equal 1, result
  ensure
    $stdin = STDIN
  end

  def test_prompt_field_with_default_input_empty_keeps_default
    runner = create_runner
    command = Slk::Commands::Preset.new([], runner: runner)
    $stdin = StringIO.new("\n")
    result = command.send(:prompt_field, 'label', 'mydefault')
    assert_equal 'mydefault', result
  ensure
    $stdin = STDIN
  end

  def test_prompt_field_with_default_input_overrides
    runner = create_runner
    command = Slk::Commands::Preset.new([], runner: runner)
    $stdin = StringIO.new("newval\n")
    result = command.send(:prompt_field, 'label', 'mydefault')
    assert_equal 'newval', result
  ensure
    $stdin = STDIN
  end

  def test_prompt_field_no_default_returns_input
    runner = create_runner
    command = Slk::Commands::Preset.new([], runner: runner)
    $stdin = StringIO.new("hello\n")
    result = command.send(:prompt_field, 'label')
    assert_equal 'hello', result
  ensure
    $stdin = STDIN
  end

  class MockPresetStore
    attr_accessor :presets

    def initialize
      @presets = {}
    end

    def all
      @presets.map { |name, data| Slk::Models::Preset.from_hash(name, data) }
    end

    def get(name)
      return nil unless @presets[name]

      Slk::Models::Preset.from_hash(name, @presets[name])
    end

    def exists?(name)
      @presets.key?(name)
    end

    def add(preset)
      @presets[preset.name] = preset.to_h
    end

    def remove(name)
      @presets.delete(name)
    end

    def on_warning=(callback); end
  end
end
