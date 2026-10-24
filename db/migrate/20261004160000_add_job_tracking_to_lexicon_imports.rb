# frozen_string_literal: true

# An import knows the job working it (job_id: the page tells queued, running
# and gone apart) and can be asked to stop (cancel_requested_at: the import
# checks it between steps, while it reads, and while its assistant test runs).
class AddJobTrackingToLexiconImports < ActiveRecord::Migration[8.1]
  def change
    add_column :lexicon_imports, :job_id, :string
    add_column :lexicon_imports, :cancel_requested_at, :datetime
  end
end
