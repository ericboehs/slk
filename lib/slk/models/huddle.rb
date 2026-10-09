# frozen_string_literal: true

module Slk
  module Models
    HuddleParticipant = Data.define(:id, :name)

    # One active huddle. `channel` is a display label filled in after the
    # scan (`#name`, `DM`, `group DM`); `channel_id` is what Slack sent.
    Huddle = Data.define(:call_id, :channel_id, :channel, :participants) do
      def place
        channel || channel_id
      end
    end

    WorkspaceHuddles = Data.define(:workspace, :huddles)
  end
end
