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

  def test_status_with_present_user_cache
    @cache_store = MockCacheStorePresent.new
    runner = create_runner
    command = Slk::Commands::Cache.new(['status'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'present'
  end

  def test_populate_cache
    @mock_client.stub('users.list', {
                        'ok' => true,
                        'members' => [
                          { 'id' => 'U1', 'name' => 'alice', 'profile' => { 'real_name' => 'Alice' } },
                          { 'id' => 'U2', 'name' => 'bob', 'profile' => { 'real_name' => 'Bob' } }
                        ]
                      })
    runner = create_runner
    command = Slk::Commands::Cache.new(['populate'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'Cached'
  end

  def test_populate_cache_paginated
    page1 = { 'ok' => true, 'members' => [user_member('U1', 'a')],
              'response_metadata' => { 'next_cursor' => 'next' } }
    page2 = { 'ok' => true, 'members' => [user_member('U2', 'b')] }
    call = 0
    @mock_client.define_singleton_method(:post) do |ws, m, params = {}|
      @calls << { workspace: ws.name, method: m, params: params }
      call += 1
      if m == 'users.list'
        call == 1 ? page1 : page2
      else
        @responses[m] || { 'ok' => true }
      end
    end
    runner = create_runner
    command = Slk::Commands::Cache.new(['populate'], runner: runner)
    assert_equal 0, command.execute
  end

  def test_refresh_alias
    @mock_client.stub('users.list', { 'ok' => true, 'members' => [] })
    runner = create_runner
    command = Slk::Commands::Cache.new(['refresh'], runner: runner)
    assert_equal 0, command.execute
  end

  def test_populate_specific_workspace
    @mock_client.stub('users.list', { 'ok' => true, 'members' => [] })
    runner = create_runner
    command = Slk::Commands::Cache.new(%w[populate test], runner: runner)
    assert_equal 0, command.execute
  end

  def test_status_multi_workspace
    workspaces = [mock_workspace('alpha'), mock_workspace('beta')]
    runner = create_runner(workspaces: workspaces)
    command = Slk::Commands::Cache.new(['status', '--all'], runner: runner)
    assert_equal 0, command.execute
    assert_includes @io.string, 'alpha'
  end

  def test_api_error_handling
    runner = create_runner
    @mock_client.define_singleton_method(:post) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'oops'
    end
    command = Slk::Commands::Cache.new(['populate'], runner: runner)
    assert_equal 1, command.execute
    assert_includes @err.string, 'Failed'
  end

  def user_member(id, name)
    { 'id' => id, 'name' => name, 'profile' => { 'real_name' => name.capitalize } }
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

    def populate_user_cache(_workspace, users)
      users.size
    end

    def on_warning=(callback); end
  end

  class MockCacheStorePresent < MockCacheStore
    def user_cache_file_exists?(_workspace) = true
  end
end
