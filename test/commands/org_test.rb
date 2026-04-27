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

  # Regression: "← you" used to be hard-coded onto the queried target,
  # so `slk org @teammate` falsely tagged the teammate as the caller.
  def test_you_marker_appears_on_self_only
    stub_chain(target_id: 'USELF', boss_id: 'UBOSS', boss_name: 'Boss')
    result = execute_with_args(['USELF'])
    assert_equal 0, result
    assert_includes io_string, 'Eric'
    assert_includes io_string, '← you'
    assert_match(/Eric.*← you/, io_string)
    refute_match(/Boss.*← you/, io_string)
  end

  def test_you_marker_absent_when_target_is_not_self
    stub_chain(target_id: 'UTEAMMATE', target_name: 'Teammate', boss_id: 'UBOSS', boss_name: 'Boss')
    result = execute_with_args(['UTEAMMATE'])
    assert_equal 0, result
    assert_includes io_string, 'Boss'
    assert_includes io_string, 'Teammate'
    refute_includes io_string, '← you'
  end

  def test_down_warns_phase_4_placeholder
    result = execute_with_args(['USELF', '--down'])
    assert_equal 0, result
    assert_includes io_string, 'lookup not yet wired'
  end

  def test_depth_option_is_respected
    # 5 levels of bosses, but --depth 2 should only render 2 supervisors above self.
    chain = (1..5).map { |i| ["UBOSS#{i}", "Boss#{i}"] }
    stub_long_chain(chain)
    execute_with_args(['USELF', '--depth', '2'])
    assert_includes io_string, 'Boss1'
    assert_includes io_string, 'Boss2'
    refute_includes io_string, 'Boss3'
  end

  def test_resolve_user_id_with_me_keyword
    result = execute_with_args(['me'])
    assert_equal 0, result
  end

  def test_resolve_user_id_with_invalid_target_raises
    cmd = Slk::Commands::Org.new(['nonsense'], runner: runner)
    result = cmd.execute
    # API error returns 1
    assert_equal 1, result
    assert_match(/Could not resolve user/, @output.instance_variable_get(:@err).string)
  end

  def test_unknown_user_via_lookup
    @mock_client.stub('users.list', { 'ok' => true, 'members' => [
                        { 'id' => 'UALEX1', 'name' => 'alex', 'real_name' => 'Alex' }
                      ] })
    @mock_client.stub('users.profile.get',
                      { 'ok' => true, 'profile' => { 'real_name' => 'Alex', 'fields' => {} } })
    @mock_client.stub('users.info', { 'ok' => true, 'user' => { 'id' => 'UALEX1', 'team_id' => 'THOME' } })
    result = execute_with_args(['@alex'])
    assert_equal 0, result
  end

  def test_resolve_user_id_via_at_handle_when_not_found_raises_api_error
    @mock_client.stub('users.list', { 'ok' => true, 'members' => [] })
    cmd = Slk::Commands::Org.new(['@unknownuser'], runner: runner)
    result = cmd.execute
    assert_equal 1, result
  end

  def test_self_user_id_is_cached
    cache = Slk::Services::CacheStore.new(paths: temp_paths)
    cache.set_meta(@workspace.name, 'self_user_id', 'UCACHED')
    runner_obj = Slk::Runner.new(output: @output, api_client: @mock_client, cache_store: cache)
    workspace = @workspace
    runner_obj.define_singleton_method(:workspace) { |_n = nil| workspace }

    @mock_client.stub('users.profile.get',
                      { 'ok' => true, 'profile' => { 'real_name' => 'Cached User', 'fields' => {} } })
    @mock_client.stub('users.info', { 'ok' => true, 'user' => { 'id' => 'UCACHED', 'team_id' => 'THOME' } })

    cmd = Slk::Commands::Org.new(['me'], runner: runner_obj)
    result = cmd.execute
    assert_equal 0, result
  end

  def test_help_shows_options
    result = execute_with_args(['--help'])
    assert_equal 0, result
    assert_includes io_string, '--up'
    assert_includes io_string, '--down'
    assert_includes io_string, '--depth'
  end

  private

  def stub_chain(target_id:, boss_id:, boss_name:, target_name: 'Eric')
    @mock_client.stub('auth.test', { 'ok' => true, 'user_id' => 'USELF' })
    seq = sequence_responder(
      'users.profile.get' => {
        target_id => { 'ok' => true, 'profile' => profile_with_supervisor(target_name, boss_id) },
        boss_id => { 'ok' => true, 'profile' => { 'real_name' => boss_name, 'fields' => {} } }
      },
      'users.info' => {
        target_id => { 'ok' => true, 'user' => { 'id' => target_id, 'team_id' => 'THOME' } },
        boss_id => { 'ok' => true, 'user' => { 'id' => boss_id, 'team_id' => 'THOME' } }
      }
    )
    @mock_client.define_singleton_method(:post_form) { |ws, m, params = {}| seq.call(ws, m, params) }
    @mock_client.define_singleton_method(:post) { |ws, m, params = {}| seq.call(ws, m, params) }
  end

  def stub_long_chain(chain)
    profiles = { 'USELF' => { 'ok' => true, 'profile' => profile_with_supervisor('Eric', chain.first.first) } }
    infos = { 'USELF' => { 'ok' => true, 'user' => { 'id' => 'USELF', 'team_id' => 'THOME' } } }
    chain.each_with_index do |(id, name), i|
      next_id = chain[i + 1]&.first
      profiles[id] =
        { 'ok' => true,
          'profile' => next_id ? profile_with_supervisor(name, next_id) : { 'real_name' => name, 'fields' => {} } }
      infos[id] = { 'ok' => true, 'user' => { 'id' => id, 'team_id' => 'THOME' } }
    end
    seq = sequence_responder('users.profile.get' => profiles, 'users.info' => infos)
    @mock_client.define_singleton_method(:post_form) { |ws, m, params = {}| seq.call(ws, m, params) }
    @mock_client.define_singleton_method(:post) { |ws, m, params = {}| seq.call(ws, m, params) }
  end

  def profile_with_supervisor(name, boss_id)
    {
      'real_name' => name, 'display_name' => name,
      'fields' => { 'XfSup' => { 'value' => boss_id, 'alt' => '', 'label' => 'Supervisor' } }
    }
  end

  def sequence_responder(per_method)
    base = @mock_client.instance_variable_get(:@responses)
    lambda do |ws, method, params = {}|
      @mock_client.calls << { workspace: ws.name, method: method, params: params }
      next per_method[method][params[:user]] if per_method.dig(method, params[:user])

      base[method] || { 'ok' => true }
    end
  end
end
