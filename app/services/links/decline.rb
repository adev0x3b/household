# frozen_string_literal: true

# A pending link goes: declined by the one asked (who tells the asker), or
# taken back by the asker (nobody is told).
module Links
  class Decline
    def self.call(link, by:)
      Broadcaster.request_settled(link) { link.destroy! }
      if by == link.addressee
        Notifications::Deliver.call(recipient: link.requester, kind: :link_declined, actor: by, title: by.display_name)
      end
      Broadcaster.changed(link.requester, link.addressee)
      link
    end
  end
end
