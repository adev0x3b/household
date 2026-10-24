# frozen_string_literal: true

# What one person may do with their linked housemates' items, from the
# LinkGrant rows given to them — read once per request (or job) and kept in
# Current, reset whenever a link or grant is saved, destroyed or rolled back.
#
#   permissions = Links::Permissions.for(profile)
#   permissions.level(owner_id, "Task", :write)  # => :on / :ask / :off
#
# One's own items are always :on; anyone else's without a grant :off.
module Links
  class Permissions
    def self.for(profile)
      memo = (Current.link_permissions ||= {})
      memo[profile.id] ||= new(profile)
    end

    def self.reset! = Current.link_permissions = nil

    def initialize(profile)
      @profile = profile
      @grants = LinkGrant.where(grantee_id: profile.id).index_by { |grant| [ grant.grantor_id, grant.event_type ] }
    end

    def level(owner_id, type, action)
      return :on if owner_id == @profile.id

      @grants[[ owner_id, type.to_s ]]&.level(action) || :off
    end

    def allows?(owner_id, type, action) = level(owner_id, type, action) != :off
    def asks?(owner_id, type, action) = level(owner_id, type, action) == :ask

    # Whose calendar a new item of this type can go on: one's own, then the
    # partners who let them add (or ask to).
    def creatable_owners(type)
      ids = @grants.values.select { |grant| grant.event_type == type.to_s && !grant.create_off? }.map(&:grantor_id)
      [ @profile ] + Profile.where(id: ids).by_name.to_a
    end
  end
end
