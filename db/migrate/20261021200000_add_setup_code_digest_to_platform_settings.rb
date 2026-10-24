# frozen_string_literal: true

# The setup page of a copy nobody has signed in to yet asks for a one-time
# code. Only its digest is kept, in the row every installation-wide value
# lives in, so the command that makes a code needs no restart to take effect.
#
# This migration first shipped under a version another migration also had,
# and a database that ran it then has the column already.
class AddSetupCodeDigestToPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_settings, :setup_code_digest, :string, if_not_exists: true
  end
end
