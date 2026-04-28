# frozen_string_literal: true

require 'test_helper'

class DebugCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @output = test_output
    @workspace = mock_workspace('test')
    stub_default_apis
  end

  def stub_default_apis
    @mock_client.stub('auth.test', { 'ok' => true, 'user_id' => 'USELF' })
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => { 'real_name' => 'Eric' } })
    @mock_client.stub('users.info', { 'ok' => true, 'user' => { 'id' => 'USELF', 'team_id' => 'THOME' } })
    @mock_client.stub('team.info', { 'ok' => true, 'team' => { 'id' => 'THOME', 'name' => 'Home' } })
    @mock_client.stub('team.profile.get', { 'ok' => true, 'profile' => { 'fields' => [], 'sections' => [] } })
  end

  def runner
    cache_store = Slk::Services::CacheStore.new(paths: temp_paths)
    runner = Slk::Runner.new(output: @output, api_client: @mock_client, cache_store: cache_store)
    workspace = @workspace
    runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    runner
  end

  def temp_paths
    @temp_paths ||= TempPaths.new
  end

  class TempPaths
    def initialize
      @dir = Dir.mktmpdir('slk-debug-test')
    end

    def cache_file(name) = File.join(@dir, name)

    def ensure_cache_dir
      FileUtils.mkdir_p(@dir)
    end
  end

  def io_string = @output.instance_variable_get(:@io).string
  def err_string = @output.instance_variable_get(:@err).string

  def execute_with_args(args)
    Slk::Commands::Debug.new(args, runner: runner).execute
  end

  def test_help
    assert_equal 0, execute_with_args(['--help'])
    assert_includes io_string, 'slk debug'
  end

  def test_dump_team
    assert_equal 0, execute_with_args(['team'])
    parsed = JSON.parse(io_string)
    assert_equal 'Home', parsed.dig('team', 'name')
  end

  def test_dump_schema
    assert_equal 0, execute_with_args(['schema'])
    parsed = JSON.parse(io_string)
    assert parsed.key?('profile')
  end

  def test_dump_profile_self
    assert_equal 0, execute_with_args(['profile'])
    parsed = JSON.parse(io_string)
    assert parsed.key?('users.profile.get')
    assert parsed.key?('users.info')
    assert parsed.key?('team.profile.get')
  end

  def test_dump_profile_me
    assert_equal 0, execute_with_args(%w[profile me])
    assert_includes io_string, 'users.profile.get'
  end

  def test_dump_profile_with_user_id
    assert_equal 0, execute_with_args(%w[profile USELF])
    assert_includes io_string, 'users.profile.get'
  end

  def test_dump_profile_unresolvable_user
    assert_equal 1, execute_with_args(%w[profile @unknown])
    assert_includes err_string, 'Could not resolve user'
  end

  def test_unknown_action
    assert_equal 1, execute_with_args(['unknown'])
    assert_includes err_string, 'Unknown debug action'
  end

  def test_api_error_handling
    @mock_client.define_singleton_method(:post) do |_ws, _m, _params = {}|
      raise Slk::ApiError, 'bad token'
    end
    assert_equal 1, execute_with_args(['team'])
    assert_includes err_string, 'API error'
  end
end
