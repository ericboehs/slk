# frozen_string_literal: true

require 'test_helper'

class CacheStoreTest < Minitest::Test
  # User cache tests
  def test_get_user_returns_nil_for_unknown_user
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      assert_nil store.get_user('workspace1', 'U123')
    end
  end

  def test_set_and_get_user
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John Doe')
      assert_equal 'John Doe', store.get_user('workspace1', 'U123')
    end
  end

  def test_user_cached_returns_false_for_unknown_user
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      refute store.user_cached?('workspace1', 'U123')
    end
  end

  def test_user_cached_returns_true_after_set
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John Doe')
      assert store.user_cached?('workspace1', 'U123')
    end
  end

  def test_user_cache_size
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      assert_equal 0, store.user_cache_size('workspace1')

      store.set_user('workspace1', 'U123', 'John')
      store.set_user('workspace1', 'U456', 'Jane')

      assert_equal 2, store.user_cache_size('workspace1')
    end
  end

  def test_clear_user_cache_for_workspace
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
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
      store = SlackCli::Services::CacheStore.new
      assert_nil store.get_channel_id('workspace1', 'general')
    end
  end

  def test_set_and_get_channel_id
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123ABC')
      assert_equal 'C123ABC', store.get_channel_id('workspace1', 'general')
    end
  end

  def test_get_channel_name_returns_name_for_id
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123ABC')
      assert_equal 'general', store.get_channel_name('workspace1', 'C123ABC')
    end
  end

  def test_channel_cache_size
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      assert_equal 0, store.channel_cache_size('workspace1')

      store.set_channel('workspace1', 'general', 'C123')
      store.set_channel('workspace1', 'random', 'C456')

      assert_equal 2, store.channel_cache_size('workspace1')
    end
  end

  def test_clear_channel_cache_for_workspace
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
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
      store = SlackCli::Services::CacheStore.new
      store.set_user('workspace1', 'U123', 'John', persist: true)

      # Create new store - should load from file
      new_store = SlackCli::Services::CacheStore.new
      assert_equal 'John', new_store.get_user('workspace1', 'U123')
    end
  end

  def test_channel_cache_persists_automatically
    with_temp_config do
      store = SlackCli::Services::CacheStore.new
      store.set_channel('workspace1', 'general', 'C123')

      # Create new store - should load from file
      new_store = SlackCli::Services::CacheStore.new
      assert_equal 'C123', new_store.get_channel_id('workspace1', 'general')
    end
  end
end
