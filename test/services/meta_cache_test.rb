# frozen_string_literal: true

require 'test_helper'

class MetaCacheTest < Minitest::Test
  Store = Struct.new(:reads, :writes, :error, keyword_init: true) do
    def get_meta(_workspace, key, ttl: nil)
      reads << [key, ttl]
      nil
    end

    def set_meta(workspace, key, value)
      raise error if error

      writes << [workspace, key, value]
    end
  end

  def store(error: nil) = Store.new(reads: [], writes: [], error: error)

  def test_write_stores_the_value
    cache = store
    Slk::Services::MetaCache.write(cache, 'ws', 'k', 'v')

    assert_equal [%w[ws k v]], cache.writes
  end

  def test_write_returns_nil_on_success
    assert_nil Slk::Services::MetaCache.write(store, 'ws', 'k', 'v')
  end

  def test_nothing_to_write_without_a_cache_or_workspace_or_value
    assert_nil Slk::Services::MetaCache.write(nil, 'ws', 'k', 'v')
    assert_nil Slk::Services::MetaCache.write(store, nil, 'k', 'v')
    assert_nil Slk::Services::MetaCache.write(store, 'ws', 'k', nil)
  end

  # A cache is an optimisation. A read-only or full disk should cost speed
  # next run, never the work already done this one.
  def test_a_disk_failure_is_returned_rather_than_raised
    error = Slk::Services::MetaCache.write(store(error: Errno::EACCES), 'ws', 'k', 'v')

    assert_kind_of Errno::EACCES, error
    assert_match(/Permission denied/, error.message)
  end

  def test_a_full_disk_is_returned_too
    assert_kind_of Errno::ENOSPC, Slk::Services::MetaCache.write(store(error: Errno::ENOSPC), 'ws', 'k', 'v')
  end

  def test_an_io_error_is_returned_too
    assert_kind_of IOError, Slk::Services::MetaCache.write(store(error: IOError), 'ws', 'k', 'v')
  end

  # A bug in the value being cached is not a disk problem and should surface.
  def test_other_errors_still_raise
    assert_raises(ArgumentError) { Slk::Services::MetaCache.write(store(error: ArgumentError), 'ws', 'k', 'v') }
  end

  def test_fetch_yields_and_writes_on_a_miss
    cache = store

    assert_equal 'computed', Slk::Services::MetaCache.fetch(cache, 'ws', 'k') { 'computed' }
    assert_equal [%w[ws k computed]], cache.writes
  end

  def test_fetch_still_returns_the_value_when_the_cache_cannot_be_written
    assert_equal 'computed', Slk::Services::MetaCache.fetch(store(error: Errno::EACCES), 'ws', 'k') { 'computed' }
  end

  def test_refresh_skips_the_read
    cache = store
    Slk::Services::MetaCache.fetch(cache, 'ws', 'k', refresh: true) { 'fresh' }

    assert_empty cache.reads
  end

  def test_read_passes_the_ttl_through
    cache = store
    Slk::Services::MetaCache.read(cache, 'ws', 'k', ttl: 60)

    assert_equal [['k', 60]], cache.reads
  end

  def test_read_without_a_cache_is_nil
    assert_nil Slk::Services::MetaCache.read(nil, 'ws', 'k')
  end
end
