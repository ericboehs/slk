# frozen_string_literal: true

module SlackCli
  module Services
    class CacheStore
      def initialize(paths: nil)
        @paths = paths || Support::XdgPaths.new
        @user_cache = {}
        @channel_cache = {}
      end

      # User cache methods
      def get_user(workspace_name, user_id)
        load_user_cache(workspace_name)
        @user_cache.dig(workspace_name, user_id)
      end

      def set_user(workspace_name, user_id, display_name, persist: false)
        load_user_cache(workspace_name)
        @user_cache[workspace_name] ||= {}
        @user_cache[workspace_name][user_id] = display_name
        save_user_cache(workspace_name) if persist
      end

      def user_cached?(workspace_name, user_id)
        load_user_cache(workspace_name)
        @user_cache.dig(workspace_name, user_id) != nil
      end

      def save_user_cache(workspace_name)
        return if @user_cache[workspace_name].nil? || @user_cache[workspace_name].empty?

        @paths.ensure_cache_dir
        file = user_cache_file(workspace_name)
        File.write(file, JSON.pretty_generate(@user_cache[workspace_name]))
      end

      def populate_user_cache(workspace_name, users)
        @user_cache[workspace_name] = {}

        users.each do |user|
          @user_cache[workspace_name][user.id] = user.best_name
        end

        save_user_cache(workspace_name)
        @user_cache[workspace_name].size
      end

      def clear_user_cache(workspace_name = nil)
        if workspace_name
          @user_cache.delete(workspace_name)
          file = user_cache_file(workspace_name)
          File.delete(file) if File.exist?(file)
        else
          @user_cache.clear
          Dir.glob(@paths.cache_file("users-*.json")).each { |f| File.delete(f) }
        end
      end

      # Channel cache methods
      def get_channel_id(workspace_name, channel_name)
        load_channel_cache(workspace_name)
        @channel_cache.dig(workspace_name, channel_name)
      end

      def get_channel_name(workspace_name, channel_id)
        load_channel_cache(workspace_name)
        cache = @channel_cache[workspace_name] || {}
        cache.key(channel_id)
      end

      def set_channel(workspace_name, channel_name, channel_id)
        @channel_cache[workspace_name] ||= {}
        @channel_cache[workspace_name][channel_name] = channel_id
        save_channel_cache(workspace_name)
      end

      def clear_channel_cache(workspace_name = nil)
        if workspace_name
          @channel_cache.delete(workspace_name)
          file = channel_cache_file(workspace_name)
          File.delete(file) if File.exist?(file)
        else
          @channel_cache.clear
          Dir.glob(@paths.cache_file("channels-*.json")).each { |f| File.delete(f) }
        end
      end

      # Cache status
      def user_cache_size(workspace_name)
        load_user_cache(workspace_name)
        @user_cache[workspace_name]&.size || 0
      end

      def channel_cache_size(workspace_name)
        load_channel_cache(workspace_name)
        @channel_cache[workspace_name]&.size || 0
      end

      def user_cache_file_exists?(workspace_name)
        File.exist?(user_cache_file(workspace_name))
      end

      def channel_cache_file_exists?(workspace_name)
        File.exist?(channel_cache_file(workspace_name))
      end

      private

      def load_user_cache(workspace_name)
        return if @user_cache.key?(workspace_name)

        file = user_cache_file(workspace_name)
        @user_cache[workspace_name] = if File.exist?(file)
          JSON.parse(File.read(file))
        else
          {}
        end
      rescue JSON::ParserError
        @user_cache[workspace_name] = {}
      end

      def load_channel_cache(workspace_name)
        return if @channel_cache.key?(workspace_name)

        file = channel_cache_file(workspace_name)
        @channel_cache[workspace_name] = if File.exist?(file)
          JSON.parse(File.read(file))
        else
          {}
        end
      rescue JSON::ParserError
        @channel_cache[workspace_name] = {}
      end

      def save_channel_cache(workspace_name)
        return if @channel_cache[workspace_name].nil? || @channel_cache[workspace_name].empty?

        @paths.ensure_cache_dir
        file = channel_cache_file(workspace_name)
        File.write(file, JSON.pretty_generate(@channel_cache[workspace_name]))
      end

      def user_cache_file(workspace_name)
        @paths.cache_file("users-#{workspace_name}.json")
      end

      def channel_cache_file(workspace_name)
        @paths.cache_file("channels-#{workspace_name}.json")
      end
    end
  end
end
