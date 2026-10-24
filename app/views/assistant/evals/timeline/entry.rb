# frozen_string_literal: true

# One entry of the timeline, drawn from the recorder's event as it was
# written: a hash of what happened. Raw tool names and JSON are fine here,
# since this is the developer's view, like the chat's debug panel.
class Views::Assistant::Evals::Timeline::Entry < Views::Base
  def initialize(event:)
    @event = event
  end
end
