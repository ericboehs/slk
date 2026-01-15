# frozen_string_literal: true

require 'test_helper'

class CacheStoreTest < Minitest::Test
  # User cache tests
  def test_get_user_returns_nil_for_unknown_user
    with_temp_config do
      store = Slk::Services::CacheStore.new
      assert_nil store.get_user('workspace1', 'U123')
    end
  end

  def test_set_and_get_user
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John Doe')
      assert_equal 'John Doe', store.get_user('workspace1', 'U123')
    end
  end

  def test_user_cached_returns_false_for_unknown_user
    with_temp_config do
      store = Slk::Services::CacheStore.new
      refute store.user_cached?('workspace1', 'U123')
    end
  end

  def test_user_cached_returns_true_after_set
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John Doe')
      assert store.user_cached?('workspace1', 'U123')
    end
  end

  def test_user_cache_size
    with_temp_config do
      store = Slk::Services::CacheStore.new
      assert_equal 0, store.user_cache_size('workspace1')

      store.set_user('workspace1', 'U123', 'John')
      store.set_user('workspace1', 'U456', 'Jane')

      assert_equal 2, store.user_cache_size('workspace1')
    end
  end

  def test_clear_user_cache_for_workspace
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John')
      store.set_user('workspace2', 'U456', 'Jane')

      store.clear_user_cache('workspace1')

      assert_nil store.get_user('workspace1', 'U123')
      assert_equal 'Jane', store.get_user('workspace2', 'U456')
    end
  end

  # Channel cache tests
  def test_get_channel_id_returns_nil_for_unknown_channel
    with_temp_config do
      store = Slk::Services::CacheStore.new
      assert_nil store.get_channel_id('workspace1', 'general')
    end
  end

  def test_set_and_get_channel_id
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123ABC')
      assert_equal 'C123ABC', store.get_channel_id('workspace1', 'general')
    end
  end

  def test_get_channel_name_returns_name_for_id
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123ABC')
      assert_equal 'general', store.get_channel_name('workspace1', 'C123ABC')
    end
  end

  def test_channel_cache_size
    with_temp_config do
      store = Slk::Services::CacheStore.new
      assert_equal 0, store.channel_cache_size('workspace1')

      store.set_channel('workspace1', 'general', 'C123')
      store.set_channel('workspace1', 'random', 'C456')

      assert_equal 2, store.channel_cache_size('workspace1')
    end
  end

  def test_clear_channel_cache_for_workspace
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123')
      store.set_channel('workspace2', 'random', 'C456')

      store.clear_channel_cache('workspace1')

      assert_nil store.get_channel_id('workspace1', 'general')
      assert_equal 'C456', store.get_channel_id('workspace2', 'random')
    end
  end

  # Persistence tests
  def test_user_cache_persists_to_file
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John', persist: true)

      # Create new store - should load from file
      new_store = Slk::Services::CacheStore.new
      assert_equal 'John', new_store.get_user('workspace1', 'U123')
    end
  end

  def test_channel_cache_persists_automatically
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123')

      # Create new store - should load from file
      new_store = Slk::Services::CacheStore.new
      assert_equal 'C123', new_store.get_channel_id('workspace1', 'general')
    end
  end

  # Subteam cache tests
  def test_get_subteam_returns_nil_for_unknown_subteam
    with_temp_config do
      store = Slk::Services::CacheStore.new
      assert_nil store.get_subteam('workspace1', 'S123')
    end
  end

  def test_set_and_get_subteam
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_subteam('workspace1', 'S123', 'platform-team')
      assert_equal 'platform-team', store.get_subteam('workspace1', 'S123')
    end
  end

  def test_subteam_cache_persists_automatically
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_subteam('workspace1', 'S123', 'devops')

      # Create new store - should load from file
      new_store = Slk::Services::CacheStore.new
      assert_equal 'devops', new_store.get_subteam('workspace1', 'S123')
    end
  end

  def test_subteam_cache_isolates_workspaces
    with_temp_config do
      store = Slk::Services::CacheStore.new
      store.set_subteam('workspace1', 'S123', 'team-a')
      store.set_subteam('workspace2', 'S123', 'team-b')

      assert_equal 'team-a', store.get_subteam('workspace1', 'S123')
      assert_equal 'team-b', store.get_subteam('workspace2', 'S123')
    end
  end

  # Cache corruption warning tests
  def test_corrupted_user_cache_triggers_warning
    with_temp_config do |dir|
      # Create a corrupted cache file
      cache_dir = "#{dir}/cache/slk"
      FileUtils.mkdir_p(cache_dir)
      File.write("#{cache_dir}/users-workspace1.json", 'not valid json{')

      warnings = []
      store = Slk::Services::CacheStore.new
      store.on_warning = ->(msg) { warnings << msg }

      # Accessing the cache should trigger the warning
      store.get_user('workspace1', 'U123')

      assert_equal 1, warnings.size
      assert_match(/User cache corrupted/, warnings.first)
    end
  end

  def test_corrupted_channel_cache_triggers_warning
    with_temp_config do |dir|
      cache_dir = "#{dir}/cache/slk"
      FileUtils.mkdir_p(cache_dir)
      File.write("#{cache_dir}/channels-workspace1.json", 'not valid json{')

      warnings = []
      store = Slk::Services::CacheStore.new
      store.on_warning = ->(msg) { warnings << msg }

      store.get_channel_id('workspace1', 'general')

      assert_equal 1, warnings.size
      assert_match(/Channel cache corrupted/, warnings.first)
    end
  end

  def test_corrupted_subteam_cache_triggers_warning
    with_temp_config do |dir|
      cache_dir = "#{dir}/cache/slk"
      FileUtils.mkdir_p(cache_dir)
      File.write("#{cache_dir}/subteams-workspace1.json", 'not valid json{')

      warnings = []
      store = Slk::Services::CacheStore.new
      store.on_warning = ->(msg) { warnings << msg }

      store.get_subteam('workspace1', 'S123')

      assert_equal 1, warnings.size
      assert_match(/Subteam cache corrupted/, warnings.first)
    end
  end
end
