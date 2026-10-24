# frozen_string_literal: true

module Uploads
  # Pushes a file's changes to its owner's pages and to the lists of every
  # housemate it is shared with, each over their own signed stream
  # (`turbo_stream_from profile, :uploads` on the Files pages). A row's
  # actions depend on who looks at it, so one render per viewer.
  #
  # DOM contract (Views::Uploads::Row, Views::Uploads::Show):
  #   upload_<id>          the row on the index
  #   upload-<id>-page     the file's page
  class Broadcaster < ApplicationBroadcaster
    # Its row redrawn for everyone who sees it, and its page for its owner
    # (the upload finished, the file renamed).
    def self.changed(upload)
      quietly do
        upload = Upload.includes(:profile, :upload_shares, :shared_profiles).find(upload.id)
        upload.people_with_access.each do |profile|
          as(profile) do
            stream_to([ profile, :uploads ], :replace, Views::Uploads::Row.new(upload: upload, viewer: profile), target: Views::Uploads::Row.dom_id(upload))
            if profile.id == upload.profile_id
              stream_to([ profile, :uploads ], :replace, Views::Uploads::Show.new(upload: upload, viewer: profile, page: Page.new(upload)), target: Views::Uploads::Show.dom_id(upload))
            end
          end
        end
      end
    end

    # Its row taken off `profiles`' pages (deleted; no longer shared with them).
    def self.removed(upload, profiles)
      quietly do
        profiles.each { |profile| stream_to([ profile, :uploads ], :remove, target: Views::Uploads::Row.dom_id(upload)) }
      end
    end
  end
end
