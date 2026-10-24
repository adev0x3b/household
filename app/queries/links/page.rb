# frozen_string_literal: true

module Links
  # What the Links page shows its viewer (Views::Links::Sections): the
  # changes they are asked to OK and the ones they asked for, link requests
  # both ways, their links, and the housemates to link with. Read for many
  # viewers in the same few queries, so a change pushed to both people of a
  # link (Links::Broadcaster) costs what one page does.
  #
  #   page = Links::Page.new([ alex, sam ])
  #   page.approvals(alex)   # => [LinkApproval, …], newest first
  #   page.housemates(sam)   # => [Profile, …]
  class Page
    # One's own requests that were answered stay listed this long…
    RECENT = 7.days
    # …and the newest this many are listed.
    REQUESTS = 20

    def initialize(viewers)
      @viewers = Array(viewers)
      @ids = @viewers.map(&:id)
    end

    def approvals(viewer) = approvals_by_owner.fetch(viewer.id, [])
    def requests(viewer) = requests_by_requester.fetch(viewer.id, []).first(REQUESTS)
    def incoming(viewer) = pending_links.select { _1.addressee_id == viewer.id }
    def outgoing(viewer) = pending_links.select { _1.requester_id == viewer.id }

    # Their links, by the partner's name.
    def links(viewer)
      accepted_links.select { _1.involves?(viewer) }.sort_by { _1.partner_of(viewer).display_name.downcase }
    end

    # Housemates with no link either way (whom one asked are `outgoing`).
    def housemates(viewer)
      taken = (pending_links + accepted_links).select { _1.involves?(viewer) }.flat_map { [ _1.requester_id, _1.addressee_id ] }
      people.select { _1.household_id == viewer.household_id && _1.id != viewer.id && taken.exclude?(_1.id) }
    end

    private

    def approvals_by_owner
      @approvals_by_owner ||= LinkApproval.live.where(owner_id: @ids).includes(:requester, :event).recent.group_by(&:owner_id)
    end

    def requests_by_requester
      @requests_by_requester ||= LinkApproval.where(requester_id: @ids)
        .where(status: :pending).or(LinkApproval.where(requester_id: @ids, decided_at: RECENT.ago..))
        .where(created_at: LinkApproval::EXPIRES_AFTER.ago..)
        .includes(:owner, :event).recent.group_by(&:requester_id)
    end

    def pending_links
      @pending_links ||= involving(Link.pending).includes(:requester, :addressee).order(:created_at).to_a
    end

    def accepted_links
      @accepted_links ||= involving(Link.accepted).includes(:requester, :addressee, :link_grants).to_a
    end

    def involving(links) = links.where(requester_id: @ids).or(links.where(addressee_id: @ids))

    # The viewers' households' joined people, in the order the page lists them.
    def people
      @people ||= Profile.joined.where(household_id: @viewers.map(&:household_id).uniq).by_name.to_a
    end
  end
end
