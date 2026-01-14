# frozen_string_literal: true

require 'test_helper'

class WorkspacesCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
    @token_store = MockTokenStore.new
    @config = MockConfig.new
  end

  def create_runner
    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| }

    SlackCli::Runner.new(
      output: @output,
      config: @config,
      token_store: @token_store,
      preset_store: preset_store,
      cache_store: cache_store
    )
  end

  def test_list_empty
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No workspaces'
  end

  def test_list_shows_workspaces
    @token_store.workspaces = { 'work' => mock_workspace('work'), 'personal' => mock_workspace('personal') }
    @config.data['primary_workspace'] = 'work'

    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'work'
    assert_includes @io.string, 'personal'
  end

  def test_list_default_action
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No workspaces'
  end

  def test_show_primary
    @config.data['primary_workspace'] = 'myworkspace'

    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['primary'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'myworkspace'
  end

  def test_show_primary_when_none_set
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['primary'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No primary'
  end

  def test_set_primary
    @token_store.workspaces = { 'newprimary' => mock_workspace('newprimary') }

    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['primary', 'newprimary'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_equal 'newprimary', @config.data['primary_workspace']
    assert_includes @io.string, 'Primary workspace set'
  end

  def test_set_primary_not_found
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['primary', 'nonexistent'], runner: runner)
    result = command.execute

    assert_includes @err.string, 'not found'
  end

  def test_remove_workspace
    @token_store.workspaces = { 'toremove' => mock_workspace('toremove') }

    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['remove', 'toremove'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Removed'
    refute @token_store.workspaces.key?('toremove')
  end

  def test_remove_workspace_not_found
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['remove', 'nonexistent'], runner: runner)
    result = command.execute

    assert_includes @err.string, 'not found'
  end

  def test_unknown_action
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['invalid'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown action'
  end

  def test_help_option
    runner = create_runner
    command = SlackCli::Commands::Workspaces.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk workspaces'
    assert_includes @io.string, 'add'
    assert_includes @io.string, 'remove'
  end

  class MockTokenStore
    attr_accessor :workspaces

    def initialize
      @workspaces = {}
    end

    def workspace(name)
      @workspaces[name] or raise SlackCli::ConfigError, "Workspace not found: #{name}"
    end

    def all_workspaces
      @workspaces.values
    end

    def workspace_names
      @workspaces.keys
    end

    def empty?
      @workspaces.empty?
    end

    def exists?(name)
      @workspaces.key?(name)
    end

    def add(name, token, cookie = nil)
      @workspaces[name] = SlackCli::Models::Workspace.new(name: name, token: token, cookie: cookie)
    end

    def remove(name)
      @workspaces.delete(name)
    end

    def on_warning=(callback); end
  end

  class MockConfig
    attr_accessor :data

    def initialize
      @data = {}
    end

    def primary_workspace
      @data['primary_workspace']
    end

    def primary_workspace=(value)
      @data['primary_workspace'] = value
    end

    def on_warning=(callback); end
  end
end
