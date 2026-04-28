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

  def test_help_option
    result = execute_with_args(['--help'])
    assert_equal 0, result
    assert_includes io_string, 'slk who'
    assert_includes io_string, '--full'
    assert_includes io_string, '--all'
    assert_includes io_string, '--pick'
  end

  def test_pick_option_with_invalid_value_raises
    err = assert_raises(Slk::ApiError) do
      Slk::Commands::Who.new(['--pick', 'foo'], runner: runner).execute
    end
    assert_match(/--pick expects an integer/, err.message)
  end

  def test_pick_option_with_integer
    cmd = Slk::Commands::Who.new(['--pick', '2'], runner: runner)
    assert_equal 2, cmd.options[:pick]
  end

  def test_refresh_option
    cmd = Slk::Commands::Who.new(['--refresh'], runner: runner)
    assert_equal true, cmd.options[:refresh]
  end

  def test_no_cache_option_aliases_refresh
    cmd = Slk::Commands::Who.new(['--no-cache'], runner: runner)
    assert_equal true, cmd.options[:refresh]
  end

  def test_all_option
    cmd = Slk::Commands::Who.new(['--all'], runner: runner)
    assert_equal true, cmd.options[:all]
  end

  def test_api_error_handling
    cmd = Slk::Commands::Who.new(['USELF'], runner: runner)
    cmd.define_singleton_method(:resolve_profiles) { |_w| raise Slk::ApiError, 'failure' }
    result = cmd.execute
    assert_equal 1, result
  end

  def test_json_with_multiple_profiles
    stub_who_resolver_two_results
    execute_with_args(['--json', '--all'])
    parsed = JSON.parse(io_string)
    assert_kind_of Array, parsed
    assert_equal 2, parsed.size
  end

  def test_render_two_profiles_uses_separator
    stub_who_resolver_two_results
    execute_with_args(['--all'])
    out = io_string
    assert_includes out, '—' * 40
  end

  private

  def stub_who_resolver_two_results
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => self_profile })
    @mock_client.stub('users.info', { 'ok' => true, 'user' => self_info })
    return if Slk::Services::WhoTargetResolver.method_defined?(:_orig_resolve)

    Slk::Services::WhoTargetResolver.alias_method(:_orig_resolve, :resolve)
    Slk::Services::WhoTargetResolver.define_method(:resolve) { |_t| %w[USELF USELF] }
  end

  def teardown
    return unless Slk::Services::WhoTargetResolver.method_defined?(:_orig_resolve)

    Slk::Services::WhoTargetResolver.alias_method(:resolve, :_orig_resolve)
    Slk::Services::WhoTargetResolver.remove_method(:_orig_resolve)
  end
end
