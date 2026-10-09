# frozen_string_literal: true

require 'test_helper'

class HuddleFetchTest < Minitest::Test
  def test_one_workspace_uses_the_shared_client
    parent = RecordingClient.new
    oddball = workspace('oddball', [member('U1', 'Ada', call_id: 'R1')])
    reports = fetch(parent, [oddball])

    assert_equal ['oddball'], reports.map(&:workspace)
    names = reports.first.huddles.flat_map { |huddle| huddle.participants.map(&:name) }
    assert_equal ['Ada'], names
    assert_empty parent.children
    refute parent.closed?
  end

  def test_several_workspaces_each_get_a_connection_and_keep_order
    parent = RecordingClient.new
    workspaces = [
      workspace('oddball', [member('U1', 'Ada', call_id: 'R1'), member('U2', 'Pat', state: 'default_unset')]),
      workspace('dsva', [member('U9', 'Quinn', call_id: 'R9')])
    ]
    reports = fetch(parent, workspaces)

    assert_equal %w[oddball dsva], reports.map(&:workspace)
    names = reports.first.huddles.flat_map { |huddle| huddle.participants.map(&:name) }
    assert_equal ['Ada'], names
    assert_equal 2, parent.children.size
    assert parent.children.all?(&:closed?)
    refute parent.closed?
  end

  def test_a_failed_workspace_still_closes_its_connection
    parent = RecordingClient.new
    workspaces = [workspace('oddball', []), workspace('dsva', [], error: 'missing_scope')]

    error = assert_raises(Slk::ApiError) { fetch(parent, workspaces) }

    assert_equal 'missing_scope', error.message
    assert parent.children.all?(&:closed?)
  end

  private

  def fetch(client, workspaces)
    runner = Struct.new(:api_client, :cache_store).new(client, cache)
    runner.define_singleton_method(:conversations_api) { |_name| nil }
    Slk::Services::HuddleFetch.new(runner: runner, output: test_output).call(workspaces)
  end

  def cache
    Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
  end

  def workspace(name, members, error: nil)
    Struct.new(:name, :roster, :error).new(name, members, error)
  end

  def member(id, name, state: 'in_a_huddle', call_id: nil)
    {
      'id' => id,
      'profile' => {
        'display_name' => name,
        'huddle_state' => state,
        'huddle_state_call_id' => call_id
      }
    }
  end

  class RecordingClient
    attr_reader :children

    def initialize(parent = nil)
      @parent = parent
      @children = []
      @closed = false
      @mutex = Mutex.new
    end

    def isolated
      self.class.new(self).tap do |child|
        @mutex.synchronize { @children << child }
      end
    end

    def post(workspace, method, _params = {})
      raise Slk::ApiError, workspace.error if workspace.error

      return { 'ok' => true, 'channel' => { 'name' => 'eert' } } if method == 'conversations.info'

      { 'ok' => true, 'members' => workspace.roster, 'response_metadata' => { 'next_cursor' => '' } }
    end

    def close
      @closed = true
    end

    def closed? = @closed
  end
end
