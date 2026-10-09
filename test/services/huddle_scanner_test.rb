# frozen_string_literal: true

require 'test_helper'

class HuddleScannerTest < Minitest::Test
  def test_groups_people_who_share_a_call_id
    huddles = scan([
                     member('U2', 'Zoe', call_id: 'R1'),
                     member('U1', 'Ada', call_id: 'R1'),
                     member('U3', 'Bea', call_id: 'R2', channel_id: 'C9')
                   ])

    assert_equal %w[R1 R2], huddles.map(&:call_id)
    assert_equal %w[Ada Zoe], huddles.first.participants.map(&:name)
    assert_equal 'C9', huddles.last.channel_id
  end

  def test_keep_drops_anyone_not_in_a_huddle
    kept = Slk::Services::HuddleScanner.keep([
                                               member('U1', 'Ada'),
                                               member('U2', 'Pat', state: 'default_unset'),
                                               { 'profile' => { 'huddle_state' => 'in_a_huddle' } }
                                             ])

    ids = kept.map { |member| member['id'] }
    assert_equal ['U1'], ids
  end

  def test_ignores_other_huddle_states
    huddles = scan([
                     member('U1', 'Ada', state: 'available_for_huddle', call_id: 'R1'),
                     member('U2', 'Bea', state: 'default_unset'),
                     member('U3', 'Cat', state: nil)
                   ])

    assert_empty huddles
  end

  def test_missing_call_id_does_not_merge_people
    huddles = scan([
                     member('U1', 'Ada', state: 'in_a_huddle'),
                     member('U2', 'Bea', state: 'in_a_huddle', call_id: '')
                   ])

    assert_equal 2, huddles.size
    assert_nil huddles.first.call_id
    assert_nil huddles.last.call_id
  end

  def test_keeps_a_channel_id_when_only_one_person_has_it
    huddles = scan([
                     member('U1', 'Ada', call_id: 'R1', channel_id: 'C1'),
                     member('U2', 'Bea', call_id: 'R1')
                   ])

    assert_equal 'C1', huddles.first.channel_id
  end

  def test_drops_disagreeing_channel_ids
    huddles = scan([
                     member('U1', 'Ada', call_id: 'R1', channel_id: 'C1'),
                     member('U2', 'Bea', call_id: 'R1', channel_id: 'C2')
                   ])

    assert_nil huddles.first.channel_id
  end

  def test_falls_back_to_handle_then_id
    huddles = scan([
                     { 'id' => 'U1', 'name' => 'ada',
                       'profile' => { 'huddle_state' => 'in_a_huddle', 'huddle_state_call_id' => 'R1' } },
                     { 'id' => 'U2', 'profile' => { 'huddle_state' => 'in_a_huddle', 'huddle_state_call_id' => 'R2' } }
                   ])

    names = huddles.to_h { |huddle| [huddle.call_id, huddle.participants.first.name] }
    assert_equal({ 'R1' => 'ada', 'R2' => 'U2' }, names)
  end

  def test_prefers_display_name_and_sorts_larger_calls_first
    huddles = scan([
                     member('U1', 'Ada', call_id: 'R1'),
                     member('U2', 'bea', display_name: 'Bea', call_id: 'R2'),
                     member('U3', 'Cat Carter', display_name: 'Cat', call_id: 'R2')
                   ])

    assert_equal 'R2', huddles.first.call_id
    assert_equal %w[Bea Cat], huddles.first.participants.map(&:name)
  end

  private

  def scan(members)
    Slk::Services::HuddleScanner.group(members)
  end

  def member(id, real_name, **attrs)
    {
      'id' => id,
      'real_name' => real_name,
      'profile' => {
        'real_name' => real_name,
        'display_name' => attrs[:display_name],
        'huddle_state' => attrs.fetch(:state, 'in_a_huddle'),
        'huddle_state_call_id' => attrs[:call_id],
        'huddle_state_channel_id' => attrs[:channel_id]
      }
    }
  end
end
