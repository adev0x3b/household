# frozen_string_literal: true

module Links
  # What waits for someone on the Links page: links they were asked for and
  # changes to their items they are asked to OK — the navbar button's count.
  # For many people at once in two queries (a change pushed to both people
  # of a link).
  class Pending
    def self.count_for(profile) = counts_for([ profile ]).fetch(profile.id)

    # { profile_id => count }
    def self.counts_for(profiles)
      ids = profiles.map(&:id)
      links = Link.pending.where(addressee_id: ids).group(:addressee_id).count
      approvals = LinkApproval.live.where(owner_id: ids).group(:owner_id).count
      ids.index_with { links.fetch(_1, 0) + approvals.fetch(_1, 0) }
    end
  end
end
