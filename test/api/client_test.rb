# frozen_string_literal: true

require 'test_helper'

class ApiClientWrapperTest < Minitest::Test
  def setup
    @api = MockApiClient.new
    @workspace = mock_workspace
    @client = Slk::Api::Client.new(@api, @workspace)
  end

  def test_counts_calls_client_counts
    @api.stub('client.counts', { 'channels' => [] })
    response = @client.counts

    assert_equal({ 'channels' => [] }, response)
    assert_equal 1, @api.call_count
    assert_equal 'client.counts', @api.calls.first[:method]
  end

  def test_auth_test_calls_auth_test
    @api.stub('auth.test', { 'team_id' => 'T1' })
    response = @client.auth_test

    assert_equal 'T1', response['team_id']
    assert_equal 'auth.test', @api.calls.first[:method]
  end

  def test_team_id_returns_team_from_auth_test
    @api.stub('auth.test', { 'team_id' => 'T123' })
    assert_equal 'T123', @client.team_id
  end

  def test_team_id_memoizes_result
    @api.stub('auth.test', { 'team_id' => 'T123' })
    @client.team_id
    @client.team_id

    auth_calls = @api.calls.count { |c| c[:method] == 'auth.test' }
    assert_equal 1, auth_calls
  end

  # unread_channels
  def test_unread_channels_filters_by_mention_count
    @api.stub('client.counts', {
                'channels' => [
                  { 'id' => 'C1', 'mention_count' => 2, 'has_unreads' => false },
                  { 'id' => 'C2', 'mention_count' => 0, 'has_unreads' => false }
                ]
              })

    result = @client.unread_channels
    assert_equal 1, result.size
    assert_equal 'C1', result.first['id']
  end

  def test_unread_channels_includes_has_unreads
    @api.stub('client.counts', {
                'channels' => [
                  { 'id' => 'C1', 'mention_count' => 0, 'has_unreads' => true },
                  { 'id' => 'C2', 'mention_count' => 0, 'has_unreads' => false }
                ]
              })

    result = @client.unread_channels
    assert_equal(['C1'], result.map { |c| c['id'] })
  end

  def test_unread_channels_handles_nil_mention_count
    @api.stub('client.counts', {
                'channels' => [
                  { 'id' => 'C1', 'has_unreads' => true },
                  { 'id' => 'C2' }
                ]
              })

    result = @client.unread_channels
    assert_equal(['C1'], result.map { |c| c['id'] })
  end

  def test_unread_channels_returns_empty_when_no_channels
    @api.stub('client.counts', {})
    assert_equal [], @client.unread_channels
  end

  def test_unread_channels_handles_nil_channels_list
    @api.stub('client.counts', { 'channels' => nil })
    assert_equal [], @client.unread_channels
  end

  # unread_dms
  def test_unread_dms_combines_ims_and_mpims
    @api.stub('client.counts', {
                'ims' => [{ 'id' => 'D1', 'mention_count' => 1 }],
                'mpims' => [{ 'id' => 'G1', 'mention_count' => 2 }]
              })

    result = @client.unread_dms
    ids = result.map { |d| d['id'] }
    assert_includes ids, 'D1'
    assert_includes ids, 'G1'
  end

  def test_unread_dms_filters_zero_mentions_without_unreads
    @api.stub('client.counts', {
                'ims' => [
                  { 'id' => 'D1', 'mention_count' => 0, 'has_unreads' => false },
                  { 'id' => 'D2', 'mention_count' => 0, 'has_unreads' => true }
                ],
                'mpims' => []
              })

    result = @client.unread_dms
    assert_equal(['D2'], result.map { |d| d['id'] })
  end

  def test_unread_dms_handles_missing_keys
    @api.stub('client.counts', {})
    assert_equal [], @client.unread_dms
  end

  def test_unread_dms_handles_nil_lists
    @api.stub('client.counts', { 'ims' => nil, 'mpims' => nil })
    assert_equal [], @client.unread_dms
  end

  # total_unread_count
  def test_total_unread_count_sums_across_keys
    @api.stub('client.counts', {
                'channels' => [{ 'mention_count' => 2 }, { 'mention_count' => 1 }],
                'ims' => [{ 'mention_count' => 3 }],
                'mpims' => [{ 'mention_count' => 4 }]
              })

    assert_equal 10, @client.total_unread_count
  end

  def test_total_unread_count_handles_nil_mention_counts
    @api.stub('client.counts', {
                'channels' => [{}, { 'mention_count' => nil }, { 'mention_count' => 5 }],
                'ims' => [],
                'mpims' => []
              })

    assert_equal 5, @client.total_unread_count
  end

  def test_total_unread_count_handles_nil_lists
    @api.stub('client.counts', { 'channels' => nil, 'ims' => nil, 'mpims' => nil })
    assert_equal 0, @client.total_unread_count
  end

  def test_total_unread_count_with_empty_response
    @api.stub('client.counts', {})
    assert_equal 0, @client.total_unread_count
  end
end
