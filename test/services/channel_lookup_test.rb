# frozen_string_literal: true

require 'test_helper'

class ChannelLookupTest < Minitest::Test
  def setup
    @client = MockApiClient.new
    @workspace = mock_workspace('oddball')
    @cache = Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
    @runner = Slk::Runner.new(output: test_output, api_client: @client, cache_store: @cache)
    workspace = @workspace
    @runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    @client.stub('conversations.list', { 'ok' => true, 'channels' => [] })
  end

  def test_cache_hit_makes_no_calls
    @cache.set_channel('oddball', 'eert', 'C1')

    assert_equal 'C1', lookup.find_id(@workspace, 'eert')
    assert_empty @client.calls
  end

  def test_named_group_dm_resolves_from_your_conversations
    stub_pages([group_dm('C0C8TMPUV3P', 'ifams review')])

    assert_equal 'C0C8TMPUV3P', lookup.find_id(@workspace, 'ifams review')
    params = @client.calls.find { |c| c[:method] == 'users.conversations' }[:params]
    assert_equal 'public_channel,private_channel,mpim', params[:types]
    assert params[:exclude_archived]
  end

  def test_pages_until_found_and_caches
    stub_pages([channel('C1', 'eert')], [group_dm('C0C8TMPUV3P', 'ifams review')])

    assert_equal 'C0C8TMPUV3P', lookup.find_id(@workspace, 'ifams review')
    assert_equal 'C0C8TMPUV3P', @cache.get_channel_id('oddball', 'ifams review')
    assert_equal(2, @client.calls.count { |c| c[:method] == 'users.conversations' })
    refute(@client.calls.any? { |c| c[:method] == 'conversations.list' })
  end

  def test_channel_match_stops_paging
    stub_pages([channel('C1', 'eert')], [channel('C2', 'other')])

    assert_equal 'C1', lookup.find_id(@workspace, 'eert')
    assert_equal(1, @client.calls.count { |c| c[:method] == 'users.conversations' })
  end

  def test_channel_beats_group_dm_with_the_same_name
    stub_pages([group_dm('C9', 'eert')], [channel('C1', 'eert')])

    assert_equal 'C1', lookup.find_id(@workspace, 'eert')
    assert_equal 'C1', @cache.get_channel_id('oddball', 'eert')
  end

  def test_match_ignores_case_and_caches_the_real_name
    stub_pages([group_dm('C0C8TMPUV3P', 'IFAMS Review')])

    assert_equal 'C0C8TMPUV3P', lookup.find_id(@workspace, 'ifams review')
    assert_equal 'IFAMS Review', @cache.get_channel_name('oddball', 'C0C8TMPUV3P')
  end

  def test_falls_back_to_first_page_of_workspace_channels
    stub_pages([channel('C1', 'eert')])
    @client.stub('conversations.list', { 'ok' => true, 'channels' => [channel('C5', 'not-joined')] })

    assert_equal 'C5', lookup.find_id(@workspace, 'not-joined')
  end

  def test_not_found_returns_nil
    stub_pages([channel('C1', 'eert')])

    assert_nil lookup.find_id(@workspace, 'nope')
  end

  def test_missing_channels_key_is_empty
    @client.stub('users.conversations', { 'ok' => true })
    @client.stub('conversations.list', { 'ok' => true })

    assert_nil lookup.find_id(@workspace, 'nope')
  end

  def test_page_cap_stops_an_endless_cursor
    @client.stub('users.conversations', { 'channels' => [], 'response_metadata' => { 'next_cursor' => 'again' } })

    assert_nil lookup.find_id(@workspace, 'nope')
    assert_equal(Slk::Services::ChannelLookup::MAX_PAGES,
                 @client.calls.count { |c| c[:method] == 'users.conversations' })
  end

  private

  def lookup
    Slk::Services::ChannelLookup.new(runner: @runner, cache_store: @cache)
  end

  def channel(id, name) = { 'id' => id, 'name' => name }
  def group_dm(id, name) = { 'id' => id, 'name' => name, 'is_mpim' => true }

  # Each argument is one page; every page but the last carries a cursor.
  def stub_pages(*pages)
    @client.stub('users.conversations', lambda { |params|
      index = params[:cursor].to_i
      next_cursor = index + 1 < pages.size ? (index + 1).to_s : ''
      { 'ok' => true, 'channels' => pages[index], 'response_metadata' => { 'next_cursor' => next_cursor } }
    })
  end
end
