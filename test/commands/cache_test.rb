# frozen_string_literal: true

require 'test_helper'

class CacheCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @cache_store = MockCacheStore.new
  end

  def create_runner(workspaces: nil)
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

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      cache_store: @cache_store,
      preset_store: preset_store
    )
  end

  def test_status_shows_cache_info
    runner = create_runner
    command = Slk::Commands::Cache.new(['status'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Users cached'
    assert_includes @io.string, 'Channels cached'
  end

  def test_status_default_action
    runner = create_runner
    command = Slk::Commands::Cache.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Users cached'
  end

  def test_info_alias
    runner = create_runner
    command = Slk::Commands::Cache.new(['info'], runner: runner)
    result = command.execute

    assert_equal 0, result
  end

  def test_clear_all
    runner = create_runner
    command = Slk::Commands::Cache.new(['clear'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert @cache_store.cleared_user
    assert @cache_store.cleared_channel
    assert_includes @io.string, 'Cleared all'
  end

  def test_clear_specific_workspace
    runner = create_runner
    command = Slk::Commands::Cache.new(%w[clear myworkspace], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_equal 'myworkspace', @cache_store.cleared_user
    assert_includes @io.string, 'myworkspace'
  end

  def test_unknown_action
    runner = create_runner
    command = Slk::Commands::Cache.new(['invalid'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown action'
  end

  def test_help_option
    runner = create_runner
    command = Slk::Commands::Cache.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk cache'
    assert_includes @io.string, 'status'
    assert_includes @io.string, 'clear'
    assert_includes @io.string, 'populate'
  end

  class MockCacheStore
    attr_reader :cleared_user, :cleared_channel

    def initialize
      @cleared_user = nil
      @cleared_channel = nil
    end

    def user_cache_size(_workspace = nil)
      0
    end

    def channel_cache_size(_workspace = nil)
      0
    end

    def user_cache_file_exists?(_workspace)
      false
    end

    def clear_user_cache(workspace = nil)
      @cleared_user = workspace || true
    end

    def clear_channel_cache(workspace = nil)
      @cleared_channel = workspace || true
    end

    def on_warning=(callback); end
  end
end
