# frozen_string_literal: true

module Deployment
  # Asks GitHub for the newest release of the one this copy runs, keeps the
  # answer for the console, and tells every admin once about each release
  # newer than theirs: an update is a command on the machine, which only
  # they can run. Returns the Deployment::Update found.
  #
  #   Deployment::CheckForUpdate.call(Deployment.release)
  class CheckForUpdate
    def self.call(running) = new(running).call

    def initialize(running)
      @running = running
    end

    def call
      Update.remember(Releases.latest(@running.repository))
      Update.for(@running).tap { tell_admins(_1.newest) if _1.available? }
    end

    private

    def tell_admins(newest)
      Profile.joined.admin.find_each do |admin|
        next if told?(admin, newest)

        Notifications::Deliver.call(recipient: admin, kind: :release_available, data: { version: newest.version })
      end
    end

    def told?(admin, newest) = admin.notifications.release_available.where("data ->> 'version' = ?", newest.version).exists?
  end
end
