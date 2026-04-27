# frozen_string_literal: true

require 'test_helper'

class ProfileResolverTest < Minitest::Test
  def setup
    @users = FakeUsersApi.new
    @team = FakeTeamApi.new(team_id: 'T_HOME')
    @resolver = Slk::Services::ProfileResolver.new(users_api: @users, team_api: @team)
  end

  def test_resolve_returns_profile
    @users.add('U001', real_name: 'Alice', display_name: 'al', team_id: 'T_HOME')
    profile = @resolver.resolve('U001')
    assert_equal 'al', profile.best_name
    refute profile.external?
  end

  def test_resolve_memoizes
    @users.add('U001', real_name: 'Alice', team_id: 'T_HOME')
    @resolver.resolve('U001')
    @resolver.resolve('U001')
    assert_equal 1, @users.calls['users.profile.get'].count { |c| c == 'U001' }
  end

  def test_external_user_attaches_home_team_name
    @users.add('U_ext', real_name: 'Tom', team_id: 'T_OTHER')
    @team.set_team('T_OTHER', name: 'innoVet Health')
    profile = @resolver.resolve('U_ext')
    assert profile.external?
    assert_equal 'innoVet Health', profile.home_team_name
  end

  def test_resolve_chain_up_walks_supervisor
    @users.add('U001', real_name: 'Eric', team_id: 'T_HOME', supervisor: 'U002')
    @users.add('U002', real_name: 'Mid', team_id: 'T_HOME', supervisor: 'U003')
    @users.add('U003', real_name: 'Top', team_id: 'T_HOME')
    chain = @resolver.resolve_chain_up('U001', depth: 5)
    assert_equal %w[Mid Top], chain.map(&:real_name)
  end

  def test_resolve_chain_up_respects_depth
    @users.add('U001', team_id: 'T_HOME', supervisor: 'U002')
    @users.add('U002', team_id: 'T_HOME', supervisor: 'U003')
    @users.add('U003', team_id: 'T_HOME')
    chain = @resolver.resolve_chain_up('U001', depth: 1)
    assert_equal %w[U002], chain.map(&:user_id)
  end

  def test_resolve_chain_up_handles_cycles
    @users.add('U001', team_id: 'T_HOME', supervisor: 'U002')
    @users.add('U002', team_id: 'T_HOME', supervisor: 'U001')
    chain = @resolver.resolve_chain_up('U001', depth: 5)
    assert_equal %w[U002], chain.map(&:user_id)
  end

  def test_resolve_with_people_resolves_referenced_users
    @users.add('U001', team_id: 'T_HOME', supervisor: 'U002,U003')
    @users.add('U002', team_id: 'T_HOME', real_name: 'Boss A')
    @users.add('U003', team_id: 'T_HOME', real_name: 'Boss B')
    profile = @resolver.resolve_with_people('U001')
    assert_equal 'Boss A', profile.resolved_users['U002'].real_name
    assert_equal 'Boss B', profile.resolved_users['U003'].real_name
  end

  class FakeUsersApi
    attr_reader :calls

    def initialize
      @users = {}
      @calls = Hash.new { |h, k| h[k] = [] }
    end

    def add(user_id, real_name: nil, display_name: nil, team_id: 'T_HOME', supervisor: nil)
      @users[user_id] = {
        info: {
          'ok' => true,
          'user' => { 'id' => user_id, 'team_id' => team_id, 'real_name' => real_name }
        },
        profile: build_profile(real_name, display_name, supervisor)
      }
    end

    def profile_for(user_id, include_labels: true) # rubocop:disable Lint/UnusedMethodArgument
      @calls['users.profile.get'] << user_id
      @users.fetch(user_id) { raise Slk::ApiError, "user_not_found: #{user_id}" }[:profile]
    end

    def info(user_id)
      @calls['users.info'] << user_id
      @users.fetch(user_id) { raise Slk::ApiError, "user_not_found: #{user_id}" }[:info]
    end

    def get_presence_for(_user_id)
      { 'presence' => 'active' }
    end

    private

    def build_profile(real_name, display_name, supervisor)
      fields = {}
      fields['Xf_super'] = { 'value' => supervisor, 'alt' => '', 'label' => 'Supervisor' } if supervisor
      {
        'ok' => true,
        'profile' => {
          'real_name' => real_name,
          'display_name' => display_name,
          'fields' => fields
        }
      }
    end
  end

  class FakeTeamApi
    def initialize(team_id:)
      @team_id = team_id
      @teams = { @team_id => { 'id' => @team_id, 'name' => 'Home' } }
    end

    def set_team(team_id, name:)
      @teams[team_id] = { 'id' => team_id, 'name' => name }
    end

    def info(team_id = nil)
      team = @teams[team_id || @team_id] || { 'id' => team_id, 'name' => nil }
      { 'ok' => true, 'team' => team }
    end

    def profile_schema
      {
        'ok' => true,
        'profile' => {
          'fields' => [
            { 'id' => 'Xf_super', 'label' => 'Supervisor', 'type' => 'user',
              'ordering' => 1, 'section_id' => 'P', 'is_hidden' => false, 'is_inverse' => false }
          ],
          'sections' => [{ 'id' => 'P', 'label' => 'People', 'order' => 1 }]
        }
      }
    end
  end
end
