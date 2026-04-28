# frozen_string_literal: true

require 'test_helper'

class WorkspacesCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @token_store = MockTokenStore.new
    @config = MockConfig.new
  end

  def create_runner
    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: @config,
      token_store: @token_store,
      preset_store: preset_store,
      cache_store: cache_store
    )
  end

  def test_list_empty
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No workspaces'
  end

  def test_list_shows_workspaces
    @token_store.workspaces = { 'work' => mock_workspace('work'), 'personal' => mock_workspace('personal') }
    @config.data['primary_workspace'] = 'work'

    runner = create_runner
    command = Slk::Commands::Workspaces.new(['list'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'work'
    assert_includes @io.string, 'personal'
  end

  def test_list_default_action
    runner = create_runner
    command = Slk::Commands::Workspaces.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No workspaces'
  end

  def test_show_primary
    @config.data['primary_workspace'] = 'myworkspace'

    runner = create_runner
    command = Slk::Commands::Workspaces.new(['primary'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'myworkspace'
  end

  def test_show_primary_when_none_set
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['primary'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'No primary'
  end

  def test_set_primary
    @token_store.workspaces = { 'newprimary' => mock_workspace('newprimary') }

    runner = create_runner
    command = Slk::Commands::Workspaces.new(%w[primary newprimary], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_equal 'newprimary', @config.data['primary_workspace']
    assert_includes @io.string, 'Primary workspace set'
  end

  def test_set_primary_not_found
    runner = create_runner
    command = Slk::Commands::Workspaces.new(%w[primary nonexistent], runner: runner)
    command.execute

    assert_includes @err.string, 'not found'
  end

  def test_remove_workspace
    @token_store.workspaces = { 'toremove' => mock_workspace('toremove') }

    runner = create_runner
    command = Slk::Commands::Workspaces.new(%w[remove toremove], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Removed'
    refute @token_store.workspaces.key?('toremove')
  end

  def test_remove_workspace_not_found
    runner = create_runner
    command = Slk::Commands::Workspaces.new(%w[remove nonexistent], runner: runner)
    command.execute

    assert_includes @err.string, 'not found'
  end

  def test_unknown_action
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['invalid'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown action'
  end

  def test_help_option
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk workspaces'
    assert_includes @io.string, 'add'
    assert_includes @io.string, 'remove'
  end

  def test_add_workspace_first_sets_primary
    fake_input = StringIO.new("alpha\nxoxb-token\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['add'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'set as primary'
    assert_equal 'alpha', @config.data['primary_workspace']
  ensure
    $stdin = STDIN
  end

  def test_add_workspace_second_does_not_set_primary
    @token_store.workspaces = { 'first' => mock_workspace('first') }
    @config.data['primary_workspace'] = 'first'
    fake_input = StringIO.new("second\nxoxb-token\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['add'], runner: runner)
    assert_equal 0, command.execute
    refute_includes @io.string, 'set as primary'
  ensure
    $stdin = STDIN
  end

  def test_add_workspace_xoxc_prompts_cookie
    fake_input = StringIO.new("oauth\nxoxc-token\nd=cookie\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['add'], runner: runner)
    assert_equal 0, command.execute
  ensure
    $stdin = STDIN
  end

  def test_add_workspace_empty_name
    fake_input = StringIO.new("\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['add'], runner: runner)
    command.execute
    assert_includes @err.string, 'Name is required'
  ensure
    $stdin = STDIN
  end

  def test_add_workspace_existing_name
    @token_store.workspaces = { 'dup' => mock_workspace('dup') }
    fake_input = StringIO.new("dup\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['add'], runner: runner)
    command.execute
    assert_includes @err.string, 'already exists'
  ensure
    $stdin = STDIN
  end

  def test_add_workspace_empty_token
    fake_input = StringIO.new("alpha\n\n")
    $stdin = fake_input
    runner = create_runner
    command = Slk::Commands::Workspaces.new(['add'], runner: runner)
    command.execute
    assert_includes @err.string, 'Token is required'
  ensure
    $stdin = STDIN
  end

  def test_remove_primary_with_remaining
    @token_store.workspaces = { 'a' => mock_workspace('a'), 'b' => mock_workspace('b') }
    @config.data['primary_workspace'] = 'a'
    runner = create_runner
    command = Slk::Commands::Workspaces.new(%w[remove a], runner: runner)
    assert_equal 0, command.execute
    assert_equal 'b', @config.data['primary_workspace']
    assert_includes @io.string, 'Primary changed'
  end

  def test_remove_primary_last_workspace
    @token_store.workspaces = { 'a' => mock_workspace('a') }
    @config.data['primary_workspace'] = 'a'
    runner = create_runner
    command = Slk::Commands::Workspaces.new(%w[remove a], runner: runner)
    assert_equal 0, command.execute
    assert_nil @config.data['primary_workspace']
  end

  class MockTokenStore
    attr_accessor :workspaces

    def initialize
      @workspaces = {}
    end

    def workspace(name)
      @workspaces[name] or raise Slk::ConfigError, "Workspace not found: #{name}"
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
      @workspaces[name] = Slk::Models::Workspace.new(name: name, token: token, cookie: cookie)
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
