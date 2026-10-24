# frozen_string_literal: true

# A username is one person's whatever its case: the model validates it so,
# and signing in compares lower(username). The index compared names as
# written, so two invitations accepted at the same moment could leave "Sam"
# and "sam", and sign-in would pick one of them. The new index compares as
# the app does, and refuses everything the old one refused, so the old one
# goes. Both are built and dropped concurrently, so neither version of the
# app waits on a lock.
class MakeUsernamesUniqueWhateverTheirCase < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    refuse_clashes
    add_index :profiles, "lower(username)", name: "index_profiles_on_lower_username", unique: true,
                                            algorithm: :concurrently, if_not_exists: true
    remove_index :profiles, :username, name: "index_profiles_on_username", algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :profiles, :username, name: "index_profiles_on_username", unique: true,
                                    algorithm: :concurrently, if_not_exists: true
    remove_index :profiles, name: "index_profiles_on_lower_username", algorithm: :concurrently, if_exists: true
  end

  private

  # Which of two people keeps the name is for a person to decide, so a clash
  # stops the deploy here, naming them, before a concurrent build fails
  # halfway and leaves an index behind that refuses nothing.
  def refuse_clashes
    clashes = select_values(<<~SQL)
      SELECT string_agg(id::text, ' and ' ORDER BY id) FROM profiles
      WHERE username IS NOT NULL GROUP BY lower(username) HAVING count(*) > 1
    SQL
    return if clashes.empty?

    raise "These profiles have one username in different cases: #{clashes.join('; ')}. " \
          "Rename one of each, then migrate again."
  end
end
