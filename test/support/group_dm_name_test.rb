# frozen_string_literal: true

require 'test_helper'

class GroupDmNameTest < Minitest::Test
  def test_flagged_group_dm_returns_its_name
    channel = { 'is_mpim' => true, 'name' => 'ifams review', 'properties' => { 'has_custom_mpdm_name' => true } }

    assert_equal 'ifams review', Slk::Support::GroupDmName.custom(channel)
  end

  # search.messages sends no properties, so the name itself has to decide.
  def test_unflagged_group_dm_with_non_slug_name_counts_as_custom
    assert_equal 'ifams review', Slk::Support::GroupDmName.custom({ 'is_mpim' => true, 'name' => 'ifams review' })
  end

  def test_generated_slug_is_not_custom
    assert_nil Slk::Support::GroupDmName.custom({ 'is_mpim' => true, 'name' => 'mpdm-a--b-1' })
  end

  def test_regular_channels_and_dms_are_not_named_group_dms
    assert_nil Slk::Support::GroupDmName.custom({ 'name' => 'general' })
    assert_nil Slk::Support::GroupDmName.custom({ 'is_im' => true, 'user' => 'U1' })
  end

  def test_blank_or_missing_input
    assert_nil Slk::Support::GroupDmName.custom({ 'is_mpim' => true, 'name' => '' })
    assert_nil Slk::Support::GroupDmName.custom(nil)
  end

  def test_label
    assert_equal '#ifams review', Slk::Support::GroupDmName.label('ifams review')
    assert_nil Slk::Support::GroupDmName.label('mpdm-a--b-1')
    assert_nil Slk::Support::GroupDmName.label(nil)
  end
end
