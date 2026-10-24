# frozen_string_literal: true

# Pushes a change to the pages people have open, as Turbo Streams.
# What every broadcaster does the same way:
#
#   as(profile) { … }      renders for one viewer at a time, in their language
#                          and on their clock: a row's actions, a bubble's
#                          "mine" or "theirs", depend on who looks
#   stream_to(…)           one action to a signed stream (`turbo_stream_from`
#                          on the page), a component rendered as its template
#   quietly { … }          a push that fails never fails what caused it — the
#                          change is already saved, the page catches up on its
#                          next visit — and is reported (Rails.error), not
#                          just logged
#
# Rendering goes through ApplicationController's renderer, outside any
# request: a fragment's host is example.org, so it builds paths, never URLs.
# Called explicitly after a write, never from a model callback. The helpers
# serve a broadcaster's class methods and, for one that carries state
# (Calendar::DayCardBroadcaster), its instances alike.
class ApplicationBroadcaster
  module Streaming
    private

    def quietly(&) = Rails.error.handle(context: { broadcaster: (is_a?(Module) ? self : self.class).name }, &)

    def as(profile, &) = profile.as_viewer(&)

    # One Turbo Stream action to the signed stream named by `streamables` (a
    # record, or the parts of a name: [ conversation, profile ]); `where` is
    # `target:` (an id) or `targets:` (a selector: every copy). Not Array():
    # it would ask a record (or a delegator) for to_ary / to_a.
    def stream_to(streamables, action, component = nil, **where)
      parts = streamables.is_a?(Array) ? streamables : [ streamables ]
      Turbo::StreamsChannel.broadcast_stream_to(*parts, content: stream_tag(action, component, **where))
    end

    # The same action, to a calendar room (CalendarChannel), not a signed stream.
    def broadcast_to_room(room, action, component = nil, **where)
      ActionCable.server.broadcast(room, stream_tag(action, component, **where))
    end

    def stream_tag(action, component = nil, **where)
      template = component && ApplicationController.render(component, layout: false)
      ApplicationController.helpers.turbo_stream_action_tag(action, **where, template: template)
    end
  end

  include Streaming
  extend Streaming
end
