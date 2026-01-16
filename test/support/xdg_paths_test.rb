# frozen_string_literal: true

require 'test_helper'

class XdgPathsTest < Minitest::Test
  WINDOWS = Gem.win_platform?

  def setup
    @paths = Slk::Support::XdgPaths.new
  end

  def test_config_dir_uses_env_var_if_set
    skip 'Unix-only test' if WINDOWS

    with_env('XDG_CONFIG_HOME' => '/custom/config') do
      paths = Slk::Support::XdgPaths.new
      assert_equal '/custom/config/slk', paths.config_dir
    end
  end

  def test_config_dir_uses_appdata_on_windows
    skip 'Windows-only test' unless WINDOWS

    with_env('APPDATA' => 'C:\Custom\AppData') do
      paths = Slk::Support::XdgPaths.new
      assert_equal 'C:\Custom\AppData/slk', paths.config_dir
    end
  end

  def test_config_dir_defaults_to_home_config
    skip 'Unix-only test' if WINDOWS

    with_env('XDG_CONFIG_HOME' => nil) do
      paths = Slk::Support::XdgPaths.new
      expected = File.join(Dir.home, '.config', 'slk')
      assert_equal expected, paths.config_dir
    end
  end

  def test_cache_dir_uses_env_var_if_set
    skip 'Unix-only test' if WINDOWS

    with_env('XDG_CACHE_HOME' => '/custom/cache') do
      paths = Slk::Support::XdgPaths.new
      assert_equal '/custom/cache/slk', paths.cache_dir
    end
  end

  def test_cache_dir_uses_localappdata_on_windows
    skip 'Windows-only test' unless WINDOWS

    with_env('LOCALAPPDATA' => 'C:\Custom\Local') do
      paths = Slk::Support::XdgPaths.new
      assert_equal 'C:\Custom\Local/slk', paths.cache_dir
    end
  end

  def test_cache_dir_defaults_to_home_cache
    skip 'Unix-only test' if WINDOWS

    with_env('XDG_CACHE_HOME' => nil) do
      paths = Slk::Support::XdgPaths.new
      expected = File.join(Dir.home, '.cache', 'slk')
      assert_equal expected, paths.cache_dir
    end
  end

  def test_config_file_joins_with_config_dir
    result = @paths.config_file('tokens.json')
    assert result.end_with?('slk/tokens.json') || result.end_with?('slk\tokens.json')
  end

  def test_cache_file_joins_with_cache_dir
    result = @paths.cache_file('emoji.json')
    assert result.end_with?('slk/emoji.json') || result.end_with?('slk\emoji.json')
  end

  def test_ensure_config_dir_creates_directory
    Dir.mktmpdir do |tmpdir|
      env_var = WINDOWS ? 'APPDATA' : 'XDG_CONFIG_HOME'
      with_env(env_var => tmpdir) do
        paths = Slk::Support::XdgPaths.new
        config_path = paths.config_dir

        refute File.exist?(config_path)
        paths.ensure_config_dir
        assert File.directory?(config_path)
      end
    end
  end

  def test_ensure_cache_dir_creates_directory
    Dir.mktmpdir do |tmpdir|
      env_var = WINDOWS ? 'LOCALAPPDATA' : 'XDG_CACHE_HOME'
      with_env(env_var => tmpdir) do
        paths = Slk::Support::XdgPaths.new
        cache_path = paths.cache_dir

        refute File.exist?(cache_path)
        paths.ensure_cache_dir
        assert File.directory?(cache_path)
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

  private

  def with_env(vars)
    old_values = {}
    vars.each do |key, value|
      old_values[key] = ENV.fetch(key, nil)
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    old_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
