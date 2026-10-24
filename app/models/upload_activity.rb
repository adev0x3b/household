# frozen_string_literal: true

# What happened to a file: uploaded, shared, downloaded (by whom), a link
# made, used or refused… Its owner reads the trail on the file's page. A
# link's use has no profile, only where it came from.
class UploadActivity < ApplicationRecord
  belongs_to :upload
  belongs_to :profile, optional: true
  belongs_to :upload_link, optional: true

  enum :action, { uploaded: 0, shared: 1, unshared: 2, downloaded: 3, link_created: 4, link_revoked: 5, link_downloaded: 6, link_refused: 7, link_locked: 8 },
       validate: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  # `request` gives where it came from; `data` what the wording needs (who
  # it was shared with, why a link was refused).
  def self.record(upload, action, actor: nil, link: nil, request: nil, **data)
    create!(upload: upload, action: action, profile: actor, upload_link: link, ip: request&.remote_ip,
            user_agent: request&.user_agent.to_s.truncate(255).presence, data: data.compact.stringify_keys)
  end
end
