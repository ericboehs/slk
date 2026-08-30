# frozen_string_literal: true

module Slk
  module Models
    # Everything `slk status` knows about one workspace at one moment: the
    # status itself, plus the two things that decide whether anyone can reach
    # you (presence, DND) and whatever is queued to replace the status later.
    #
    # Every part but the status is optional, and nil means "not checked" —
    # skipped by a flag, or a lookup that failed. That is deliberately distinct
    # from checked-and-empty: `scheduled: []` says nothing is queued, while
    # `scheduled: nil` says nobody looked.
    StatusSnapshot = Data.define(:workspace, :status, :presence, :dnd, :scheduled) do
      def initialize(workspace:, status:, presence: nil, dnd: nil, scheduled: nil)
        super
      end

      def workspace_name = workspace.name

      def away? = presence ? presence[:presence] == 'away' : false

      # Short suffixes for the status line. Only the exceptional states appear:
      # active presence and DND-off are the common case, and repeating them on
      # every line would bury the workspace that differs.
      def labels
        [('[away]' if away?), dnd&.to_s].reject { |label| label.to_s.empty? }
      end
    end
  end
end
