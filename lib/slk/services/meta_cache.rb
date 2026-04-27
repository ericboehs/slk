# frozen_string_literal: true

module Slk
  module Services
    # Read-through wrapper around CacheStore#get_meta/#set_meta with optional
    # TTL and refresh override. Used by ProfileResolver and similar services.
    module MetaCache
      module_function

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

      def write(cache_store, workspace_name, key, value)
        return unless cache_store && workspace_name && value

        cache_store.set_meta(workspace_name, key, value)
      end
    end
  end
end
