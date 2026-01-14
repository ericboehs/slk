# frozen_string_literal: true

require 'test_helper'

class XdgPathsTest < Minitest::Test
  def setup
    @paths = SlackCli::Support::XdgPaths.new
  end

  def test_config_dir_uses_xdg_config_home_if_set
    original = ENV.fetch('XDG_CONFIG_HOME', nil)
    begin
      ENV['XDG_CONFIG_HOME'] = '/custom/config'
      paths = SlackCli::Support::XdgPaths.new
      assert_equal '/custom/config/slk', paths.config_dir
    ensure
      ENV['XDG_CONFIG_HOME'] = original
    end
  end

  def test_config_dir_defaults_to_home_config
    original = ENV.fetch('XDG_CONFIG_HOME', nil)
    begin
      ENV.delete('XDG_CONFIG_HOME')
      paths = SlackCli::Support::XdgPaths.new
      expected = File.join(Dir.home, '.config', 'slk')
      assert_equal expected, paths.config_dir
    ensure
      ENV['XDG_CONFIG_HOME'] = original
    end
  end

  def test_cache_dir_uses_xdg_cache_home_if_set
    original = ENV.fetch('XDG_CACHE_HOME', nil)
    begin
      ENV['XDG_CACHE_HOME'] = '/custom/cache'
      paths = SlackCli::Support::XdgPaths.new
      assert_equal '/custom/cache/slk', paths.cache_dir
    ensure
      ENV['XDG_CACHE_HOME'] = original
    end
  end

  def test_cache_dir_defaults_to_home_cache
    original = ENV.fetch('XDG_CACHE_HOME', nil)
    begin
      ENV.delete('XDG_CACHE_HOME')
      paths = SlackCli::Support::XdgPaths.new
      expected = File.join(Dir.home, '.cache', 'slk')
      assert_equal expected, paths.cache_dir
    ensure
      ENV['XDG_CACHE_HOME'] = original
    end
  end

  def test_config_file_joins_with_config_dir
    result = @paths.config_file('tokens.json')
    assert result.end_with?('slk/tokens.json')
  end

  def test_cache_file_joins_with_cache_dir
    result = @paths.cache_file('emoji.json')
    assert result.end_with?('slk/emoji.json')
  end

  def test_ensure_config_dir_creates_directory
    Dir.mktmpdir do |tmpdir|
      original = ENV.fetch('XDG_CONFIG_HOME', nil)
      begin
        ENV['XDG_CONFIG_HOME'] = tmpdir
        paths = SlackCli::Support::XdgPaths.new
        config_path = paths.config_dir

        refute File.exist?(config_path)
        paths.ensure_config_dir
        assert File.directory?(config_path)
      ensure
        ENV['XDG_CONFIG_HOME'] = original
      end
    end
  end

  def test_ensure_cache_dir_creates_directory
    Dir.mktmpdir do |tmpdir|
      original = ENV.fetch('XDG_CACHE_HOME', nil)
      begin
        ENV['XDG_CACHE_HOME'] = tmpdir
        paths = SlackCli::Support::XdgPaths.new
        cache_path = paths.cache_dir

        refute File.exist?(cache_path)
        paths.ensure_cache_dir
        assert File.directory?(cache_path)
      ensure
        ENV['XDG_CACHE_HOME'] = original
      end
    end
  end

  def test_directories_are_memoized
    dir1 = @paths.config_dir
    dir2 = @paths.config_dir
    assert_same dir1, dir2

    cache1 = @paths.cache_dir
    cache2 = @paths.cache_dir
    assert_same cache1, cache2
  end
end
