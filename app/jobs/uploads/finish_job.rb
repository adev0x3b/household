# frozen_string_literal: true

module Uploads
  # The last chunk is in: the file is checked against the size declared,
  # its SHA-256 worked out (shown on its page, for whoever wants to check
  # a download), its content type read from its first bytes rather than
  # taken from the browser, and it is ready — to share, to link, to
  # download. A file whose size doesn't match goes back to uploading from
  # where the disk says it is. The owner hears about it under the bell
  # when it took a while (NOTIFY_AFTER), not for every small file.
  #
  # A virus scan, when one is wanted (ClamAV's clamdscan on `upload.path`),
  # belongs here, between the size check and `ready`.
  class FinishJob < ApplicationJob
    queue_as :default

    NOTIFY_AFTER = 1.minute

    def perform(upload)
      return unless upload.processing?

      size = Storage.size(upload.key)
      return upload.update!(status: :uploading, received_bytes: size) if size != upload.byte_size

      checksum = Storage.sha256(upload.key)
      content_type = Storage.content_type(upload.key, name: upload.name, declared: upload.content_type)
      # The sweep may have started this check again beside one that was
      # only slow: whichever finishes first makes the file ready.
      upload.with_lock do
        return unless upload.processing?

        upload.update!(status: :ready, completed_at: Time.current, checksum: checksum, content_type: content_type)
      end
      UploadActivity.record(upload, :uploaded, actor: upload.profile)
      Broadcaster.changed(upload)
      notify(upload.profile_id, :upload_ready, subject: upload) if upload.created_at < NOTIFY_AFTER.ago
    end
  end
end
