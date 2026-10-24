# frozen_string_literal: true

# The modal for each kind of press on the pipeline (Delivery::Presses),
# found by the press's kind: what the press will do, then what it needs.
# The frame they share is Modals::Base.
module Views::Admin::Deliveries::Modals
  def self.for(press)
    { preview: Preview, merge: Merge, stop: Stop, ci: Ci, deploy: Deploy, restart: Restart,
      rollback: Rollback, release: Release, freeze: Freeze, unfreeze: Unfreeze }.fetch(press.kind).new(press: press)
  end
end
