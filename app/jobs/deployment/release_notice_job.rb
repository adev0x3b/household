# frozen_string_literal: true

module Deployment
  # Tells every member of this installation when a release with downtime
  # starts and how it ended. Production only; which runs were told is kept in
  # Solid Cache, whose database a release's undo doesn't touch.
  class ReleaseNoticeJob < ApplicationJob
    runs_outside_web_server

    # A run that ended longer ago than this is old news (the job may have been stopped meanwhile).
    RECENT = 2.hours

    # A release rehearses on staging first, so its starting notice lands
    # minutes before the maintenance page.
    def perform
      return unless Deployment.destination == "production" && Delivery::Github.configured?

      Delivery::Github.workflow_runs(limit: 10).each do |run|
        next unless run.event == "workflow_dispatch" && run.title.start_with?("release ")

        if run.live?
          tell_once(run, :release_starting)
        elsif run.updated_at && run.updated_at > RECENT.ago
          tell_once(run, run.succeeded? ? :release_finished : :release_undone)
        end
      end
    rescue Delivery::Github::Error => e
      Rails.error.report(e, handled: true, context: { job: self.class.name })
    end

    private

    def tell_once(run, kind)
      key = "deployment/release-notice/#{run.id}/#{kind}"
      return if Rails.cache.read(key)

      Rails.cache.write(key, true, expires_in: 2.days)
      version = run.title[/\bat (\h{7})/, 1]
      Profile.joined.find_each do |profile|
        Notifications::Deliver.call(recipient: profile, kind: kind, data: { version: version, run_url: run.html_url })
      end
    end
  end
end
