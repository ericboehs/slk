# frozen_string_literal: true

require 'test_helper'

class PresetCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
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
    token_store.define_singleton_method(:on_warning=) { |_| }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { workspace_list.first&.name }
    config.define_singleton_method(:on_warning=) { |_| }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:[]) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| }

    ps = preset_store || @preset_store
    ps.define_singleton_method(:on_warning=) { |_| } unless ps.respond_to?(:on_warning=)

    SlackCli::Runner.new(
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
    command = SlackCli::Commands::Preset.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No presets'
  end

  def test_list_presets_shows_presets
    @preset_store.presets = {
      'meeting' => { 'text' => 'In a meeting', 'emoji' => ':calendar:', 'duration' => '1h', 'presence' => '', 'dnd' => '' }
    }
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'meeting'
    assert_includes @io.string, 'In a meeting'
  end

  def test_list_presets_default_action
    @preset_store.presets = {}
    runner = create_runner
    command = SlackCli::Commands::Preset.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No presets'
  end

  def test_ls_alias
    @preset_store.presets = {}
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['ls'], runner: runner)
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
    command = SlackCli::Commands::Preset.new(['lunch'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, "Applied preset 'lunch'"
  end

  def test_apply_preset_not_found
    @preset_store.presets = {}
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['nonexistent'], runner: runner)
    result = command.execute

    assert_includes @err.string, 'not found'
  end

  def test_delete_preset
    @preset_store.presets = { 'lunch' => {} }
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['delete', 'lunch'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'deleted'
  end

  def test_delete_preset_rm_alias
    @preset_store.presets = { 'lunch' => {} }
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['rm', 'lunch'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'deleted'
  end

  def test_delete_preset_not_found
    @preset_store.presets = {}
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['delete', 'nonexistent'], runner: runner)
    result = command.execute

    assert_includes @err.string, 'not found'
  end

  def test_help_option
    runner = create_runner
    command = SlackCli::Commands::Preset.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk preset'
    assert_includes @io.string, 'list'
    assert_includes @io.string, 'add'
  end

  class MockPresetStore
    attr_accessor :presets

    def initialize
      @presets = {}
    end

    def all
      @presets.map { |name, data| SlackCli::Models::Preset.from_hash(name, data) }
    end

    def get(name)
      return nil unless @presets[name]

      SlackCli::Models::Preset.from_hash(name, @presets[name])
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
