# frozen_string_literal: true

module Delivery
  # The app's own record of a press, kept beside the GitHub run it becomes.
  # The console polls it right after a press, before GitHub lists the run.
  class Request < ApplicationRecord
    # The table keeps the console's old name: renaming it needs the app
    # stopped (lib/held_migrations.rb), and a name isn't worth a release.
    self.table_name = "deployment_requests"

    # Pressed lately: the console polls until the run shows up.
    WATCH_FOR = 5.minutes

    belongs_to :profile

    # `merge_branch`, not `merge`: Active Record owns that class method. A
    # preview and a merge keep their branch in `ref`, and a merge keeps the
    # commit it made on main in `version`.
    enum :action, { ci: 0, deploy: 1, restart: 2, rollback: 3, release: 4, freeze: 5, unfreeze: 6, preview: 7, merge_branch: 8, stop: 9 }, validate: true
    enum :status, { requested: 0, running: 1, succeeded: 2, failed: 3, lost: 4 }, validate: true

    validates :destination, inclusion: { in: Deployment::DESTINATIONS }, allow_nil: true

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :live, -> { where(status: %i[requested running]) }
    scope :watching, -> { live.where(created_at: WATCH_FOR.ago..) }

    def live? = requested? || running?
    def ended? = !live?
    def short_version = version&.first(7)

    # What the run's inputs say: who asked, the id this record is found
    # again by, and the admin's own words.
    def reason_for_github
      "#{profile.username} from the app ##{id}#{": #{reason}" if reason.present?}"
    end

    # Takes a run's state: running, or how it ended.
    def follow!(run)
      if run.live?
        update!(run_id: run.id, run_url: run.html_url, status: :running)
      else
        update!(run_id: run.id, run_url: run.html_url, status: run.succeeded? ? :succeeded : :failed, summary: run.state, finished_at: run.updated_at || Time.current)
      end
    end
  end
end
