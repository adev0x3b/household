# frozen_string_literal: true

module Uploads
  # What a file's page shows its owner besides the file (Views::Uploads::Show):
  # the links made to it and what happened to it, newest first. Read by
  # whoever draws the page: UploadsController, UploadLinksController when a
  # link changes, Uploads::Broadcaster when the file does.
  class Page
    # The trail's newest entries; the page says how many older ones there are.
    ACTIVITY = 50

    def initialize(upload)
      @upload = upload
    end

    def links = @links ||= @upload.upload_links.includes(:profile).newest_first.to_a

    def activity = @activity ||= @upload.upload_activities.includes(:profile).recent_first.limit(ACTIVITY).to_a

    def older_activity = [ @upload.upload_activities.count - activity.size, 0 ].max
  end
end
