# frozen_string_literal: true

module Delivery
  # Follows a press until its GitHub run ends, then tells whoever pressed. On
  # production the job worker stops during a release, so the job picks up
  # again when the new version boots, which is when there is news.
  class WatchJob < ApplicationJob
    runs_outside_web_server

    EVERY = 30.seconds
    GIVE_UP = 90.minutes

    def perform(request_id)
      request = Request.find_by(id: request_id)
      return if request.nil? || request.ended?

      run = Presses.for_action(request.action).find_run(request)
      if run
        request.follow!(run)
        return tell(request) if request.ended?
      elsif request.created_at < GIVE_UP.ago
        request.update!(status: :lost, finished_at: Time.current)
        return tell(request)
      end

      self.class.set(wait: EVERY).perform_later(request_id)
    rescue Github::Error => e
      Rails.error.report(e, handled: true, context: { job: self.class.name, request_id: request_id })
      self.class.set(wait: EVERY).perform_later(request_id)
    end

    private

    # A lost request has no run to quote, so the bell words why from its outcome.
    def tell(request)
      notify(request.profile_id, request.succeeded? ? :deploy_succeeded : :deploy_failed,
             action: request.action, destination: request.destination, version: request.short_version, ref: request.ref,
             **(request.lost? ? { outcome: "lost" } : { detail: request.summary }))
    end
  end
end
