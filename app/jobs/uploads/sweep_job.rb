# frozen_string_literal: true

module Uploads
  # Uploads nobody finished (a tab closed, a laptop shut) are given up on
  # after Upload::ABANDONED_AFTER: their bytes go and their reserved size
  # is given back to the household. A file whose check stalled (it failed,
  # or a restart lost it) is checked again, and given up on after the same
  # time, its owner told, since they saw it go up. Every hour
  # (config/recurring.yml). One that can't be removed is reported and tried
  # again at the next sweep.
  class SweepJob < ApplicationJob
    queue_as :default

    def perform
      Upload.abandoned.find_each { |upload| on_its_own(upload) { Destroy.call(upload) } }
      Upload.check_stalled.find_each { |upload| on_its_own(upload) { check_again_or_give_up(upload) } }
    end

    private

    def check_again_or_give_up(upload)
      return FinishJob.perform_later(upload) if upload.updated_at >= Upload::ABANDONED_AFTER.ago

      Destroy.call(upload)
      Notifications::Deliver.call(recipient: upload.profile, kind: :upload_failed, title: upload.name)
    end
  end
end
