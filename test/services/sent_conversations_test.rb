# frozen_string_literal: true

require_relative '../test_helper'

class SentConversationsTest < Minitest::Test
  def setup
    @acme = mock_workspace('acme')
    @dsva = mock_workspace('dsva')
    @runner = Object.new
    @runner.define_singleton_method(:conversations_api) { |_workspace| Object.new }
  end

  def test_equal_start_times_use_workspace_then_channel_identity
    entries = [[@dsva, hit('100.0', 'C9')], [@dsva, hit('100.0', 'C1')], [@acme, hit('100.0', 'C5')]]

    conversations = service.collect(entries)

    order = conversations.map { |conversation| [conversation.workspace.name, conversation.channel_id] }
    assert_equal [%w[acme C5], %w[dsva C1], %w[dsva C9]], order
  end

  def test_order_does_not_lose_fractional_timestamp_precision
    older = hit('9999999999.000001', 'C9')
    newer = hit('9999999999.000002', 'C1')
    assert_equal older.ts.to_f, newer.ts.to_f # The float sort key would treat these as a tie.

    conversations = service.collect([[@acme, newer], [@acme, older]])

    assert_equal %w[C9 C1], conversations.map(&:channel_id)
  end

  private

  def service
    Slk::Services::SentConversations.new(runner: @runner, start_date: Date.new(2026, 9, 22),
                                         end_date: Date.new(2026, 9, 22), before: 0, after_minutes: 0)
  end

  def hit(timestamp, channel_id)
    Slk::Models::SearchResult.from_api('ts' => timestamp, 'user' => 'U1', 'text' => 'Sent message',
                                       'channel' => { 'id' => channel_id, 'name' => channel_id.downcase })
  end
end
