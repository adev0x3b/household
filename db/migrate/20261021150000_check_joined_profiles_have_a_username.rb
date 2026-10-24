# frozen_string_literal: true

# Someone who has joined signs in with a username, so the profile validates
# one unless the invitation is still waiting for an answer. The database
# holds a write that goes around the model to it too.
#
# Added without checking the rows there are, which would hold a lock on the
# table while the version still serving writes to it; the next migration
# checks them.
class CheckJoinedProfilesHaveAUsername < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :profiles, "invitation_token IS NOT NULL OR coalesce(btrim(username), '') <> ''",
                         name: "profiles_username_unless_invited", validate: false
  end
end
