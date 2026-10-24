# frozen_string_literal: true

module Uploads
  # The first step of an upload: the row, with the file's name and declared
  # size, before any byte comes. Refused when the household's storage
  # can't take it (the size is reserved from now), when the file is bigger
  # than one may be, or when the name is no good. The reason is a key under
  # `uploads.errors`.
  #
  #   result = Uploads::Create.call(owner: current_profile, name: "holiday.mp4", byte_size: 12_345, content_type: "video/mp4")
  #   result.upload   # saved, status uploading
  #   result.success? # false: result.error is :quota, :too_large or :invalid
  class Create
    Result = ServiceResult.define(:upload)

    # The quota is checked and the size reserved under the household's lock:
    # two uploads started together can't both fit in the space of one.
    def self.call(owner:, name:, byte_size:, content_type: nil)
      upload = owner.uploads.new(name: name, byte_size: byte_size.to_i, content_type: content_type.to_s.first(100).presence)
      return Result.new(upload: upload, error: :too_large) if upload.byte_size > Upload::MAX_SIZE

      owner.household.with_lock do
        next Result.new(upload: upload, error: :quota) unless Quota.new(owner.household).fits?(upload.byte_size)

        Result.new(upload: upload, error: upload.save ? nil : :invalid)
      end
    end
  end
end
