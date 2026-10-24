# frozen_string_literal: true

# Why an approved request couldn't be done, as a reason each reader's page
# words in their own language. The words it replaces (link_approvals.error)
# were written in the approver's language; that column goes in a later
# release, once no running version writes it.
class AddFailureToLinkApprovals < ActiveRecord::Migration[8.1]
  def change
    add_column :link_approvals, :failure, :integer
  end
end
