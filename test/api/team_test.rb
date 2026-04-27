# frozen_string_literal: true

require 'test_helper'

class TeamApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::Team.new(@mock_client, @workspace)
  end

  def test_info_without_team_id
    @mock_client.stub('team.info', { 'ok' => true, 'team' => { 'id' => 'T1', 'name' => 'Acme' } })

    response = @api.info
    assert_equal 'Acme', response['team']['name']

    call = @mock_client.calls.last
    assert_equal 'team.info', call[:method]
    assert_equal({}, call[:params])
  end

  def test_info_with_team_id
    @mock_client.stub('team.info', { 'ok' => true, 'team' => { 'id' => 'T2', 'name' => 'External' } })

    @api.info('T2')

    call = @mock_client.calls.last
    assert_equal 'T2', call[:params][:team]
  end

  def test_profile_schema
    @mock_client.stub('team.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'fields' => [
                            { 'id' => 'Xf01', 'label' => 'Supervisor', 'type' => 'user', 'ordering' => 0 }
                          ]
                        }
                      })

    response = @api.profile_schema
    assert_equal 'Supervisor', response['profile']['fields'].first['label']

    call = @mock_client.calls.last
    assert_equal 'team.profile.get', call[:method]
  end

  def test_profile_schema_with_visibility
    @mock_client.stub('team.profile.get', { 'ok' => true, 'profile' => { 'fields' => [] } })
    @api.profile_schema(visibility: 'all')

    call = @mock_client.calls.last
    assert_equal 'all', call[:params][:visibility]
  end
end
