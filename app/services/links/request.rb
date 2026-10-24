# frozen_string_literal: true

# One housemate asks another to link (LinkPolicy#create? first). If the
# other already asked, this accepts theirs instead. Returns the Link.
module Links
  class Request
    def self.call(from:, to:)
      existing = Link.between(from, to)
      return Accept.call(existing) if existing&.pending? && existing.addressee_id == from.id
      return existing if existing

      link = Link.create!(requester: from, addressee: to)
      Notifications::Deliver.call(recipient: to, kind: :link_requested, subject: link, actor: from)
      Broadcaster.changed(to)
      link
    end
  end
end
