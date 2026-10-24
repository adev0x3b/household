# frozen_string_literal: true

# A file kept on the server (the Files section, /files): first the upload
# in progress, then the file once it is whole. Private to whoever uploaded
# it until shared with a housemate (UploadShare) or handed to anyone by a
# link (UploadLink); everything that happens to it is an UploadActivity.
#
# The bytes live outside the database and outside Active Storage, under
# `storage/files` (Uploads::Storage), named by `key` alone: the name the
# person gave is kept here, cleaned (Uploads::Filename), and goes back out
# as the download's filename. A 10 GB file comes up in chunks of
# CHUNK_SIZE (the Cloudflare tunnel in front of production refuses a
# request body over 100 MB): the row is made first with the size declared
# (Uploads::Create), the chunks are appended in order (Uploads::Append,
# `received_bytes` says how far), and once the last one is in,
# Uploads::FinishJob checks the size, works out the SHA-256 and the content
# type, and the file is `ready`. An upload nobody finishes is swept after
# ABANDONED_AFTER, and one whose check stalled is checked again, then given
# up on too (Uploads::SweepJob).
#
# The declared size counts against the household's quota from the start
# (Uploads::Quota), so two uploads can't both fit in the last gigabyte.
class Upload < ApplicationRecord
  include Searchable
  include Shareable

  # What one request carries. Under Cloudflare's 100 MB; big enough that a
  # 10 GB file is some 640 requests.
  CHUNK_SIZE = 16.megabytes
  # A chunk larger than this is refused outright.
  MAX_CHUNK = 64.megabytes
  # One file, at most.
  MAX_SIZE = 50.gigabytes
  # An upload untouched this long is given up on.
  ABANDONED_AFTER = 24.hours
  # A check takes minutes, even for the largest file: one still going after
  # this long failed, or was lost with the worker running it.
  CHECK_STALLED_AFTER = 1.hour
  NAME_LENGTH = 255

  # What a file is, by its content type: the page words it (uploads.kinds)
  # and draws it (Views::Uploads::Icon) by this.
  KINDS = {
    image: [ %r{\Aimage/} ], video: [ %r{\Avideo/} ], audio: [ %r{\Aaudio/} ], pdf: [ %r{\Aapplication/pdf\z} ],
    archive: [ %r{zip|tar|gzip|x-7z|x-rar|x-bzip|compressed} ],
    spreadsheet: [ %r{spreadsheet|excel|csv} ], presentation: [ %r{presentation|powerpoint} ],
    document: [ %r{msword|wordprocessing|opendocument\.text|rtf} ], text: [ %r{\Atext/} ]
  }.freeze

  belongs_to :profile
  shared_through :upload_shares

  # The section of the household it belongs to (the share modal's colour).
  def section = :files
  has_many :upload_links, dependent: :destroy
  has_many :upload_activities, dependent: :destroy

  enum :status, { uploading: 0, processing: 1, ready: 2 }, validate: true

  searchable_by :name

  normalizes :name, with: ->(value) { Uploads::Filename.clean(value) }
  before_validation { self.key ||= SecureRandom.uuid }

  validates :name, presence: true, length: { maximum: NAME_LENGTH }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SIZE }
  validates :received_bytes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :key, presence: true, uniqueness: true, format: { with: Uploads::Storage::KEY }

  # One's own, and what housemates shared with one.
  scope :accessible_by, ->(profile) {
    where_id_in_any(unscoped.where(profile_id: profile.id).select(:id), UploadShare.where(profile_id: profile.id).select(:upload_id))
  }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :abandoned, -> { uploading.where(updated_at: ...ABANDONED_AFTER.ago) }
  scope :check_stalled, -> { processing.where(updated_at: ...CHECK_STALLED_AFTER.ago) }

  def path = Uploads::Storage.path(key)

  def complete? = received_bytes >= byte_size

  # 0..100, of the bytes received.
  def percent = byte_size.positive? ? (received_bytes * 100.0 / byte_size).floor.clamp(0, 100) : 0

  def kind
    type = content_type.to_s
    KINDS.find { |_, patterns| patterns.any? { |pattern| type.match?(pattern) } }&.first || :file
  end

  # Its extension, for the row ("PDF", "ZIP"); nothing when there is none.
  def extension = File.extname(name).delete_prefix(".").upcase.presence

  # Sharing (Shareable): only a whole file; each share and unshare goes on
  # the file's trail, and an unshared file leaves the person's list.
  def shareable? = ready?

  def on_shared(share, by:)
    UploadActivity.record(self, :shared, actor: by, with: share.profile.display_name)
  end

  def on_unshared(share, by:)
    UploadActivity.record(self, :unshared, actor: by, with: share.profile.display_name)
    Uploads::Broadcaster.removed(self, [ share.profile ])
  end
end
