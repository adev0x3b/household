# frozen_string_literal: true

# Either side ends an accepted link: its grants and the requests waiting on
# it go with it, both calendars lose the other's items, and the other side
# hears about it.
module Links
  class Unlink
    def self.call(link, by:)
      partner = link.partner_of(by)
      Broadcaster.request_settled(link) { link.destroy! }
      Notifications::Deliver.call(recipient: partner, kind: :link_removed, actor: by, title: by.display_name)
      Calendar::Refresh.call(by, partner)
      Broadcaster.changed(by, partner)
      link
    end
  end
end
