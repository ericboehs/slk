# frozen_string_literal: true

require 'test_helper'

class EmojiSearcherTest < Minitest::Test
  def setup
    @cache_dir = Dir.mktmpdir
    @emoji_dir = Dir.mktmpdir
    @workspace = mock_workspace('ws1')
  end

  def teardown
    FileUtils.rm_rf(@cache_dir)
    FileUtils.rm_rf(@emoji_dir)
  end

  def searcher(on_debug: nil)
    Slk::Services::EmojiSearcher.new(
      cache_dir: @cache_dir, emoji_dir: @emoji_dir, on_debug: on_debug
    )
  end

  def write_gemoji(content)
    File.write(File.join(@cache_dir, 'gemoji.json'), JSON.dump(content))
  end

  def test_search_standard_emoji
    write_gemoji('fire' => "\u{1F525}", 'water' => "\u{1F4A7}")
    results = searcher.search('fire')
    assert results['standard']
    assert_equal 1, results['standard'].size
  end

  def test_search_returns_empty_when_no_gemoji_cache
    results = searcher.search('fire')
    assert_empty results.fetch('standard', [])
  end

  def test_search_handles_corrupted_gemoji_json
    File.write(File.join(@cache_dir, 'gemoji.json'), '{not valid')
    debug = []
    s = searcher(on_debug: ->(m) { debug << m })
    s.search('fire')
    assert(debug.any? { |m| m.include?('cache corrupted') })
  end

  def test_search_workspace_emoji
    workspace_dir = File.join(@emoji_dir, 'ws1')
    FileUtils.mkdir_p(workspace_dir)
    File.write(File.join(workspace_dir, 'partyparrot.gif'), 'data')
    File.write(File.join(workspace_dir, 'happy.png'), 'data')

    results = searcher.search('party', workspaces: [@workspace])
    assert_equal 1, results['ws1'].size
    assert_equal 'partyparrot', results['ws1'].first[:name]
  end

  def test_search_workspace_returns_empty_when_dir_missing
    results = searcher.search('foo', workspaces: [@workspace])
    refute_includes results.keys, 'ws1'
  end

  def test_search_combines_standard_and_workspace
    write_gemoji('fire' => "\u{1F525}")
    workspace_dir = File.join(@emoji_dir, 'ws1')
    FileUtils.mkdir_p(workspace_dir)
    File.write(File.join(workspace_dir, 'firealarm.png'), 'data')

    results = searcher.search('fire', workspaces: [@workspace])
    assert_equal 1, results['standard'].size
    assert_equal 1, results['ws1'].size
  end

  def test_search_is_case_insensitive
    write_gemoji('FIRE' => "\u{1F525}")
    results = searcher.search('fire')
    assert_equal 1, results['standard'].size
  end

  def test_search_standard_method_returns_empty_when_cache_missing
    assert_empty searcher.search_standard(/fire/)
  end

  def test_search_workspace_method_directly
    workspace_dir = File.join(@emoji_dir, 'ws1')
    FileUtils.mkdir_p(workspace_dir)
    File.write(File.join(workspace_dir, 'cool.png'), 'data')
    results = searcher.search_workspace(@workspace, /cool/)
    assert_equal 'cool', results.first[:name]
  end
end
