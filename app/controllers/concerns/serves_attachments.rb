# frozen_string_literal: true

# Sends a stored file (Active Storage) from a controller that has just
# authorized it. Active Storage's own routes are off (config/application.rb):
# their signed URLs never expire and would hand a file to anyone holding
# one. A file never changes, so the browser that asked may keep it; nothing
# in between may.
module ServesAttachments
  extend ActiveSupport::Concern

  private

  def send_attachment(blob)
    expires_in 1.year, public: false, immutable: true
    send_data blob.download, type: blob.content_type_for_serving, disposition: "inline", filename: blob.filename.sanitized
  end
end
