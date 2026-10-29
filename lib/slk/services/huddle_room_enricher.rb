# frozen_string_literal: true

module Slk
  module Services
    # Adds what profiles no longer say to one workspace's huddles: the
    # channel, and Slack Connect guests missing from users.list.
    #
    # huddles.get runs once per call id, and users.info once per guest whose
    # name is not cached, both on a small worker pool so a busy workspace
    # does not wait on dozens of requests in a row. Workspaces are scanned
    # concurrently too, so cache reads and writes go through cache_mutex.
    class HuddleRoomEnricher
      WORKERS = 4

      def initialize(workspace:, client:, cache_store:, cache_mutex:, on_debug: nil)
        @workspace = workspace
        @client = client
        @cache = cache_store
        @cache_mutex = cache_mutex
        @on_debug = on_debug
      end

      def call(huddles)
        rooms = fan_out(huddles) { |huddle, client| room_for(huddle, client) }
        names = guest_names(guest_ids(huddles, rooms))
        HuddleScanner.sort(huddles.zip(rooms).map { |huddle, room| apply(huddle, room, names) })
      end

      private

      def fan_out(items, &)
        PooledFanout.call(items, workers: WORKERS, client: @client, &)
      end

      def room_for(huddle, client)
        return nil if huddle.channel_id || huddle.call_id.nil?

        HuddleRoom.new(api_client: client, workspace: @workspace, on_debug: @on_debug).lookup(huddle.call_id)
      end

      def guest_ids(huddles, rooms)
        huddles.zip(rooms).flat_map do |huddle, room|
          room ? room.participant_ids - huddle.participants.map(&:id) : []
        end.uniq
      end

      def guest_names(ids)
        cached = cached_names(ids)
        missing = ids - cached.keys
        fetched = missing.zip(fan_out(missing) { |id, client| fetch_name(id, client) }).to_h.compact
        remember(fetched)
        cached.merge(fetched)
      end

      def cached_names(ids)
        @cache_mutex.synchronize { ids.to_h { |id| [id, @cache.get_user(@workspace.name, id)] }.compact }
      end

      def fetch_name(user_id, client)
        user = Api::Users.new(client, @workspace, on_debug: @on_debug).info(user_id)['user']
        user && Models::User.from_api(user).best_name
      rescue ApiError => e
        @on_debug&.call("User lookup failed for #{user_id}: #{e.message}")
        nil
      end

      def remember(names)
        return if names.empty?

        @cache_mutex.synchronize do
          names.each { |id, name| @cache.set_user(@workspace.name, id, name) }
          @cache.save_user_cache(@workspace.name)
        end
      end

      def apply(huddle, room, names)
        return huddle unless room

        known = huddle.participants.map(&:id)
        added = (room.participant_ids - known).map do |id|
          Models::HuddleParticipant.new(id: id, name: names[id] || id)
        end
        huddle.with(channel_id: room.channel_id,
                    participants: HuddleScanner.sort_participants(huddle.participants + added))
      end
    end
  end
end
