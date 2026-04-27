# frozen_string_literal: true

require 'test_helper'

class OrgCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @output = test_output
    @workspace = mock_workspace('test')
    setup_team_stubs
    setup_user_chain
  end

  def setup_team_stubs
    @mock_client.stub('auth.test', { 'ok' => true, 'user_id' => 'USELF' })
    @mock_client.stub('team.info', { 'ok' => true, 'team' => { 'id' => 'THOME', 'name' => 'Home' } })
    @mock_client.stub('team.profile.get', team_schema)
  end

  def team_schema
    {
      'ok' => true,
      'profile' => {
        'fields' => [
          { 'id' => 'XfSup', 'label' => 'Supervisor', 'type' => 'user',
            'ordering' => 1, 'section_id' => 'P', 'is_hidden' => false, 'is_inverse' => false }
        ],
        'sections' => [{ 'id' => 'P', 'label' => 'People', 'order' => 1 }]
      }
    }
  end

  def setup_user_chain
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => self_profile })
    @mock_client.stub('users.info', { 'ok' => true, 'user' => self_info })
  end

  def self_profile
    {
      'real_name' => 'Eric', 'display_name' => 'Eric', 'title' => 'Engineer',
      'fields' => { 'XfSup' => { 'value' => 'UMID', 'alt' => '', 'label' => 'Supervisor' } }
    }
  end

  def self_info
    { 'id' => 'USELF', 'team_id' => 'THOME', 'tz' => 'America/Chicago', 'tz_label' => 'CDT' }
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
      @dir = Dir.mktmpdir('slk-org-test')
    end

    def cache_file(name)
      File.join(@dir, name)
    end

    def ensure_cache_dir
      FileUtils.mkdir_p(@dir)
    end
  end

  def io_string = @output.instance_variable_get(:@io).string

  def execute_with_args(args)
    Slk::Commands::Org.new(args, runner: runner).execute
  end

  def test_runs_without_supervisor
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => { 'real_name' => 'Eric', 'fields' => {} } })
    result = execute_with_args(['USELF'])
    assert_equal 0, result
    assert_includes io_string, 'No supervisor'
  end

  def test_unknown_action_help_shown
    result = execute_with_args(['--help'])
    assert_equal 0, result
    assert_includes io_string, 'slk org'
  end
end
