# frozen_string_literal: true

require 'test_helper'

class HuddleChannelLabelTest < Minitest::Test
  def setup
    @workspace = mock_workspace('oddball')
    @cache = Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
    @debug = []
    @channels = {}
    @runner = Object.new
    channels = @channels
    @runner.define_singleton_method(:conversations_api) do |_name|
      api = Object.new
      api.define_singleton_method(:info) do |channel:|
        found = channels[channel]
        raise Slk::ApiError, 'channel_not_found' unless found

        { 'channel' => found }
      end
      api
    end
  end

  def test_blank_channel_id
    assert_nil labeler.label(@workspace, nil)
    assert_nil labeler.label(@workspace, '')
  end

  def test_named_channel_is_cached
    @channels['C1'] = { 'id' => 'C1', 'name' => 'eert' }

    assert_equal '#eert', labeler.label(@workspace, 'C1')
    @channels.clear
    assert_equal '#eert', labeler.label(@workspace, 'C1')
  end

  def test_group_dm_is_not_cached_as_a_name
    @channels['G1'] = { 'id' => 'G1', 'is_mpim' => true, 'name' => 'mpdm-a--b-1' }

    assert_equal 'group DM', labeler.label(@workspace, 'G1')
    assert_nil @cache.get_channel_name(@workspace.name, 'G1')
  end

  def test_blank_name
    @channels['C2'] = { 'id' => 'C2', 'name' => '' }

    assert_nil labeler.label(@workspace, 'C2')
  end

  def test_lookup_failure_is_debug_not_a_raise
    assert_nil labeler.label(@workspace, 'Cmissing')
    assert_match(/channel_not_found/, @debug.first)
  end

  private

  def labeler
    Slk::Services::HuddleChannelLabel.new(
      runner: @runner, cache_store: @cache, on_debug: ->(message) { @debug << message }
    )
  end
end
