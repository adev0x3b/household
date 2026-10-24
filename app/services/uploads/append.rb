# frozen_string_literal: true

module Uploads
  # One chunk of an upload, appended where the file has got to. The row is
  # locked for the append, so two chunks can't interleave; a chunk sent at
  # the wrong offset (a retry of one that did arrive) is refused with the
  # real offset, and the client goes on from there. The last chunk hands
  # the file to Uploads::FinishJob.
  #
  #   result = Uploads::Append.call(upload, io: request.body, offset: 16.megabytes, length: request.content_length)
  #   result.error    # nil when appended, else :conflict, :too_large, :not_uploading
  #   result.offset   # the file's size after the call: what the client sends next
  class Append
    Result = ServiceResult.define(:offset)

    def self.call(upload, io:, offset:, length:)
      result = nil
      upload.with_lock do
        result =
          if !upload.uploading? then Result.new(error: :not_uploading, offset: upload.received_bytes)
          elsif offset != upload.received_bytes then Result.new(error: :conflict, offset: upload.received_bytes)
          elsif length.nil? || length > Upload::MAX_CHUNK || offset + length > upload.byte_size
            Result.new(error: :too_large, offset: upload.received_bytes)
          else
            append(upload, io, offset, length)
          end
      end
      result
    end

    def self.append(upload, io, offset, length)
      written = Storage.append(upload.key, io, at: offset)
      upload.update!(received_bytes: offset + written)
      if upload.complete?
        upload.update!(status: :processing)
        FinishJob.perform_later(upload)
      end
      Result.new(error: (:conflict unless written == length), offset: upload.received_bytes)
    rescue Storage::Mismatch
      # The file on disk and the row disagree (a crash between the two): the disk is right.
      upload.update!(received_bytes: Storage.size(upload.key))
      Result.new(error: :conflict, offset: upload.received_bytes)
    end
    private_class_method :append
  end
end
