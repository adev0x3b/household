# frozen_string_literal: true

# An invited person picks their username when they accept: until then the
# profile has none (the unique index ignores NULLs, where it allowed a
# single "").
class AllowProfilesWithoutUsername < ActiveRecord::Migration[8.1]
  def up
    change_column_default :profiles, :username, from: "", to: nil
    change_column_null :profiles, :username, true
    execute("UPDATE profiles SET username = NULL WHERE username = ''")
  end

  def down
    execute("UPDATE profiles SET username = '' WHERE username IS NULL")
    change_column_null :profiles, :username, false
    change_column_default :profiles, :username, from: nil, to: ""
  end
end
