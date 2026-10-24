# frozen_string_literal: true

module UploadBuilders
  # A file kept whole, the way an upload ends up: the row, its bytes under
  # storage, checked and ready (Uploads::FinishJob).
  def keep_file(owner, name: "notes.txt", content: "hello there\n", content_type: nil)
    result = Uploads::Create.call(owner: owner, name: name, byte_size: content.bytesize, content_type: content_type)
    raise "couldn't keep #{name}: #{result.error}" unless result.success?

    Uploads::Append.call(result.upload, io: StringIO.new(content), offset: 0, length: content.bytesize)
    Uploads::FinishJob.perform_now(result.upload.reload)
    result.upload.reload
  end

  # The bytes a fixture upload stands for, written where the app will look.
  def write_upload_file(upload, content)
    Uploads::Storage.delete(upload.key)
    Uploads::Storage.append(upload.key, StringIO.new(content), at: 0)
    upload
  end

  def mint_link(upload, by: upload.profile, **options)
    UploadLink.mint(upload: upload, by: by, **options)
  end
end
