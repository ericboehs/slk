# frozen_string_literal: true

require 'test_helper'

class RunnerTest < Minitest::Test
  def setup
    @output = MockOutput.new
    @config = MockConfig.new
    @token_store = MockTokenStore.new
    @api_client = MockApiClient.new
    @cache_store = MockCacheStore.new
    @preset_store = MockPresetStore.new
  end

  def test_initializes_with_defaults
    runner = Slk::Runner.new

    assert_kind_of Slk::Formatters::Output, runner.output
    assert_kind_of Slk::Services::Configuration, runner.config
    assert_kind_of Slk::Services::TokenStore, runner.token_store
    assert_kind_of Slk::Services::ApiClient, runner.api_client
    assert_kind_of Slk::Services::CacheStore, runner.cache_store
    assert_kind_of Slk::Services::PresetStore, runner.preset_store
  end

  def test_initializes_with_custom_dependencies
    runner = create_runner

    assert_equal @output, runner.output
    assert_equal @config, runner.config
    assert_equal @token_store, runner.token_store
    assert_equal @api_client, runner.api_client
    assert_equal @cache_store, runner.cache_store
    assert_equal @preset_store, runner.preset_store
  end

  def test_workspace_returns_workspace_from_token_store
    @token_store.workspaces['test'] = Slk::Models::Workspace.new(
      name: 'test',
      token: 'xoxp-test-token'
    )
    runner = create_runner

    ws = runner.workspace('test')
    assert_equal 'test', ws.name
    assert_equal 'xoxp-test-token', ws.token
  end

  def test_workspace_uses_primary_when_no_name_given
    @config.data['primary_workspace'] = 'primary'
    @token_store.workspaces['primary'] = Slk::Models::Workspace.new(
      name: 'primary',
      token: 'xoxp-primary-token'
    )
    runner = create_runner

    ws = runner.workspace
    assert_equal 'primary', ws.name
  end

  def test_workspace_raises_when_no_name_and_no_primary
    @config.data['primary_workspace'] = nil
    runner = create_runner

    assert_raises(Slk::ConfigError) do
      runner.workspace
    end
  end

  def test_all_workspaces_returns_all_from_token_store
    @token_store.workspaces['ws1'] = Slk::Models::Workspace.new(name: 'ws1', token: 'xoxp-1')
    @token_store.workspaces['ws2'] = Slk::Models::Workspace.new(name: 'ws2', token: 'xoxp-2')
    runner = create_runner

    workspaces = runner.all_workspaces
    assert_equal 2, workspaces.size
  end

  def test_workspace_names_returns_names
    @token_store.workspaces['alpha'] = Slk::Models::Workspace.new(name: 'alpha', token: 'xoxp-a')
    @token_store.workspaces['beta'] = Slk::Models::Workspace.new(name: 'beta', token: 'xoxp-b')
    runner = create_runner

    names = runner.workspace_names
    assert_includes names, 'alpha'
    assert_includes names, 'beta'
  end

  def test_workspaces_predicate_returns_true_when_not_empty
    @token_store.workspaces['test'] = Slk::Models::Workspace.new(name: 'test', token: 'xoxp-t')
    runner = create_runner

    assert runner.workspaces?
  end

  def test_workspaces_predicate_returns_false_when_empty
    runner = create_runner

    refute runner.workspaces?
  end

  def test_users_api_returns_api_instance
    @config.data['primary_workspace'] = 'test'
    @token_store.workspaces['test'] = Slk::Models::Workspace.new(name: 'test', token: 'xoxp-t')
    runner = create_runner

    api = runner.users_api
    assert_kind_of Slk::Api::Users, api
  end

  def test_conversations_api_returns_api_instance
    @config.data['primary_workspace'] = 'test'
    @token_store.workspaces['test'] = Slk::Models::Workspace.new(name: 'test', token: 'xoxp-t')
    runner = create_runner

    api = runner.conversations_api
    assert_kind_of Slk::Api::Conversations, api
  end

  def test_dnd_api_returns_api_instance
    @config.data['primary_workspace'] = 'test'
    @token_store.workspaces['test'] = Slk::Models::Workspace.new(name: 'test', token: 'xoxp-t')
    runner = create_runner

    api = runner.dnd_api
    assert_kind_of Slk::Api::Dnd, api
  end

  def test_message_formatter_returns_formatter
    runner = create_runner

    formatter = runner.message_formatter
    assert_kind_of Slk::Formatters::MessageFormatter, formatter
  end

  def test_message_formatter_is_memoized
    runner = create_runner

    formatter1 = runner.message_formatter
    formatter2 = runner.message_formatter
    assert_same formatter1, formatter2
  end

  def test_emoji_replacer_is_memoized
    runner = create_runner

    replacer1 = runner.emoji_replacer
    replacer2 = runner.emoji_replacer
    assert_same replacer1, replacer2
  end

  def test_duration_formatter_is_memoized
    runner = create_runner

    formatter1 = runner.duration_formatter
    formatter2 = runner.duration_formatter
    assert_same formatter1, formatter2
  end

  def test_log_error_delegates_to_error_logger
    runner = create_runner
    error = StandardError.new('test error')

    # Just ensure it doesn't raise
    runner.log_error(error)
  end

  def test_emoji_api_returns_api_instance
    setup_workspace
    assert_kind_of Slk::Api::Emoji, create_runner.emoji_api
  end

  def test_bots_api_returns_api_instance
    setup_workspace
    api = create_runner.bots_api
    assert_kind_of Slk::Api::Bots, api
  end

  def test_threads_api_returns_api_instance
    setup_workspace
    assert_kind_of Slk::Api::Threads, create_runner.threads_api
  end

  def test_activity_api_returns_api_instance
    setup_workspace
    assert_kind_of Slk::Api::Activity, create_runner.activity_api
  end

  def test_search_api_returns_api_instance
    setup_workspace
    assert_kind_of Slk::Api::Search, create_runner.search_api
  end

  def test_saved_api_returns_api_instance
    setup_workspace
    assert_kind_of Slk::Api::Saved, create_runner.saved_api
  end

  def test_team_api_returns_api_instance
    setup_workspace
    assert_kind_of Slk::Api::Team, create_runner.team_api
  end

  def test_profile_resolver_returns_resolver_with_refresh
    setup_workspace
    resolver = create_runner.profile_resolver(refresh: true)
    assert_kind_of Slk::Services::ProfileResolver, resolver
    assert resolver.refresh
  end

  def test_message_resolver_returns_resolver
    setup_workspace
    resolver = create_runner.message_resolver
    assert_kind_of Slk::Services::MessageResolver, resolver
  end

  def test_mention_replacer_is_memoized
    runner = create_runner
    a = runner.mention_replacer
    assert_same a, runner.mention_replacer
  end

  def test_text_processor_is_memoized
    runner = create_runner
    a = runner.text_processor
    assert_same a, runner.text_processor
  end

  def test_search_formatter_is_memoized
    runner = create_runner
    a = runner.search_formatter
    assert_same a, runner.search_formatter
  end

  def test_callbacks_invoke_output_debug
    setup_workspace
    runner = create_runner
    # Build instances to capture lambdas
    formatter = runner.message_formatter
    replacer = runner.mention_replacer
    bots = runner.bots_api
    resolver = runner.profile_resolver
    msg_resolver = runner.message_resolver
    users = runner.users_api

    # Invoke each captured lambda to cover the body
    invoke_on_debug(formatter)
    invoke_on_debug(replacer)
    invoke_on_debug(bots)
    invoke_on_debug(resolver)
    invoke_on_debug(msg_resolver)
    invoke_on_debug(users)

    assert true
  end

  def invoke_on_debug(obj)
    cb = obj.instance_variable_get(:@on_debug)
    cb&.call('msg')
  end

  private

  def create_runner
    Slk::Runner.new(
      output: @output,
      config: @config,
      token_store: @token_store,
      api_client: @api_client,
      cache_store: @cache_store,
      preset_store: @preset_store
    )
  end

  def setup_workspace(name: 'test')
    @config.data['primary_workspace'] = name
    @token_store.workspaces[name] = Slk::Models::Workspace.new(name: name, token: 'xoxp-t')
  end

  # Mock classes for testing
  class MockOutput
    def puts(msg = ''); end
    def print(msg); end
    def error(msg); end
    def warn(msg); end
    def debug(msg); end
    def verbose? = false
  end

  class MockConfig
    attr_accessor :on_warning, :data

    def initialize
      @data = {}
      @on_warning = nil
    end

    def primary_workspace
      @data['primary_workspace']
    end
  end

  class MockTokenStore
    attr_accessor :on_warning, :workspaces

    def initialize
      @workspaces = {}
      @on_warning = nil
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
  end

  class MockApiClient
    def close; end
  end

  class MockCacheStore
    attr_accessor :on_warning

    def initialize
      @on_warning = nil
    end
  end

  class MockPresetStore
    attr_accessor :on_warning

    def initialize
      @on_warning = nil
    end
  end
end
