# frozen_string_literal: true

module Uploads
  # A file gone: its shares, links and trail with it (the row cascades),
  # then its bytes. Deleting from the index, the page, the sweep of
  # abandoned uploads, and Profiles::Destroy for whole people.
  class Destroy
    def self.call(upload)
      key = upload.key
      upload.destroy!
      Storage.delete(key)
      upload
    end
  end
end
