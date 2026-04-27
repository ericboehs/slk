# frozen_string_literal: true

require 'test_helper'

class WhoCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @output = test_output
    @workspace = mock_workspace('test')
    stub_workspace_apis
  end

  def stub_workspace_apis
    @mock_client.stub('auth.test', { 'ok' => true, 'user_id' => 'USELF' })
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => self_profile })
    @mock_client.stub('users.info', { 'ok' => true, 'user' => self_info })
    @mock_client.stub('team.info', { 'ok' => true, 'team' => { 'id' => 'T_HOME', 'name' => 'Home' } })
    @mock_client.stub('team.profile.get', team_schema)
  end

  def self_profile
    {
      'real_name' => 'Eric Boehs', 'display_name' => 'Eric',
      'title' => 'Senior Engineer', 'email' => 'eric@example.com', 'phone' => '555',
      'fields' => {
        'Xf01' => { 'value' => '2020-01-15', 'alt' => '', 'label' => 'Start Date' }
      }
    }
  end

  def self_info
    { 'id' => 'USELF', 'team_id' => 'T_HOME', 'tz' => 'America/Chicago',
      'tz_label' => 'CDT', 'tz_offset' => -18_000 }
  end

  def team_schema
    {
      'ok' => true,
      'profile' => {
        'fields' => [
          { 'id' => 'Xf01', 'label' => 'Start Date', 'type' => 'date',
            'ordering' => 1, 'section_id' => 'S1', 'is_hidden' => false, 'is_inverse' => false }
        ],
        'sections' => [{ 'id' => 'S1', 'label' => 'About', 'order' => 1 }]
      }
    }
  end

  def runner
    cache_store = Slk::Services::CacheStore.new(paths: temp_paths)
    runner = Slk::Runner.new(output: @output, api_client: @mock_client, cache_store: cache_store)
    runner.token_store.define_singleton_method(:workspace) { |_name = nil| nil }
    runner.token_store.define_singleton_method(:all_workspaces) { [] }
    runner.token_store.define_singleton_method(:workspace_names) { [] }
    runner.token_store.define_singleton_method(:empty?) { true }
    workspace = @workspace
    runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    runner
  end

  def temp_paths
    @temp_paths ||= TempPaths.new
  end

  class TempPaths
    def initialize
      @dir = Dir.mktmpdir('slk-who-test')
    end

    def cache_file(name)
      File.join(@dir, name)
    end

    def ensure_cache_dir
      FileUtils.mkdir_p(@dir)
    end
  end

  def execute_with_args(args)
    Slk::Commands::Who.new(args, runner: runner).execute
  end

  def io_string
    @output.instance_variable_get(:@io).string
  end

  def test_self_profile_compact
    result = execute_with_args([])
    assert_equal 0, result
    assert_includes io_string, 'Eric'
    assert_includes io_string, 'Senior Engineer'
    assert_includes io_string, 'eric@example.com'
    assert_includes io_string, 'Jan 15, 2020'
  end

  def test_full_layout
    execute_with_args(['--full'])
    out = io_string
    assert_includes out, 'Contact information'
    assert_includes out, 'About me'
  end

  def test_json_output
    execute_with_args(['--json'])
    parsed = JSON.parse(io_string)
    assert_equal 'USELF', parsed['user_id']
    assert parsed['custom_fields'].is_a?(Array)
  end

  def test_explicit_user_id
    execute_with_args(['USELF'])
    assert_includes io_string, 'Eric'
  end
end
