# frozen_string_literal: true

module Delivery
  # Every kind of press on the pipeline. A link or a form names one by its
  # kind, a recorded request by its action.
  module Presses
    def self.all = [ Preview, Merge, Stop, Ci, Deploy, Restart, Rollback, Release, Freeze, Unfreeze ]

    # Nil for a kind there isn't, which only a hand-made link can name.
    def self.for(kind) = all.find { _1.kind.to_s == kind.to_s }
    def self.for_action(action) = all.find { _1.action == action.to_s }
  end
end
