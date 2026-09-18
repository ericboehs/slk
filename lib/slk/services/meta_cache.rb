# frozen_string_literal: true

module Slk
  module Services
    # Read-through wrapper around CacheStore#get_meta/#set_meta with optional
    # TTL and refresh override. Used by ProfileResolver and similar services.
    module MetaCache
      module_function

      # A write failure here is deliberately dropped: fetch's caller wants the
      # value, and callers that need to report a cold cache use write directly.
      def fetch(cache_store, workspace_name, key, ttl: nil, refresh: false)
        cached = read(cache_store, workspace_name, key, ttl: ttl) unless refresh
        return cached if cached

        value = yield
        write(cache_store, workspace_name, key, value)
        value
      end

      def read(cache_store, workspace_name, key, ttl: nil)
        return nil unless cache_store && workspace_name

        cache_store.get_meta(workspace_name, key, ttl: ttl)
      end

      # A cache write that fails must never cost the caller the work it just
      # did — a full or read-only disk means "no cache", not "no answer", and
      # some of these writes sit behind minutes of rate-limited API calls.
      #
      # A nil or false value is treated as nothing to store, since no caller
      # caches a negative this way — the start date lookup caches per-user
      # nils inside a Hash, which is a value like any other.
      #
      # @return [Exception, nil] the write failure, for callers that want to
      #   mention it; nil when the write succeeded or there was nothing to do
      def write(cache_store, workspace_name, key, value)
        return nil unless cache_store && workspace_name && value

        cache_store.set_meta(workspace_name, key, value)
        nil
      rescue SystemCallError, IOError => e
        e
      end
    end
  end
end
