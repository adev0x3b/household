# frozen_string_literal: true

# Whether a person's address is theirs, confirmed by a link mailed to it,
# and a new address waiting for its own link. The link's token is kept as a
# digest, with when it was sent and a digest of the address it was made
# for. Empty on every existing profile: nobody has confirmed an address
# yet. The index is built without blocking writes.
class AddEmailConfirmationToProfiles < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :profiles, :email_confirmed_at, :datetime, if_not_exists: true
    add_column :profiles, :unconfirmed_email, :string, if_not_exists: true
    add_column :profiles, :email_confirmation_digest, :string, if_not_exists: true
    add_column :profiles, :email_confirmation_sent_at, :datetime, if_not_exists: true
    add_column :profiles, :email_confirmation_address_digest, :string, if_not_exists: true
    add_index :profiles, :email_confirmation_digest, name: "index_profiles_on_email_confirmation_digest", unique: true,
                                                     algorithm: :concurrently, if_not_exists: true
  end
end
