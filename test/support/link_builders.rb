# frozen_string_literal: true

# Links between housemates for tests: accepted, with every kind's grants
# at their defaults (read on, the rest asked), tuned with `grant`.
module LinkBuilders
  def link!(one, other)
    link = Link.create!(requester: one, addressee: other, status: :accepted, accepted_at: Time.current)
    link.ensure_grants!
    link
  end

  # What `grantor` lets `grantee` do with their series of `type`.
  def grant(grantor, grantee, type, **levels)
    LinkGrant.find_by!(grantor: grantor, grantee: grantee, event_type: type)
      .update!(levels.transform_keys { |action| :"#{action}_level" })
  end
end
