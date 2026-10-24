# frozen_string_literal: true

# The addressee says yes: the link starts with every type granted both
# ways at the defaults (read on, the rest asked), both calendars redraw
# with the other's items, and the requester hears about it.
module Links
  class Accept
    def self.call(link)
      Link.transaction do
        link.update!(status: :accepted, accepted_at: Time.current)
        link.ensure_grants!
      end
      Notifications::Deliver.call(recipient: link.requester, kind: :link_accepted, subject: link, actor: link.addressee)
      Broadcaster.request_settled(link)
      Calendar::Refresh.call(link.requester, link.addressee)
      Broadcaster.changed(link.requester, link.addressee)
      link
    end
  end
end
