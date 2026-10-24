# frozen_string_literal: true

module Messages
  # A picture as a message keeps it: turned the way the camera held it, then
  # saved again without its metadata — where it was taken, the phone, the
  # time — as messengers do. The people it is sent to see the picture, not
  # where it was taken.
  #
  #   results = images.map { Messages::CleanPicture.call(_1) }
  #   results.first.picture # what to attach, unless the result has an error
  #
  # What a file is comes from its bytes, never from the type the browser
  # declared, so a photo sent as a GIF is still cleaned. A GIF is kept as it
  # came (saving it again would lose its animation, and it carries no
  # location), and so is one too large to keep, for Message's validations to
  # name. A file that isn't a picture is refused as such; a picture that
  # can't be saved again is refused rather than kept with its metadata, and
  # reported, since a picture the app can't read is the app's to fix.
  class CleanPicture
    FORMATS = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze
    QUALITY = 90 # JPEG and WebP: saved again, close to the original

    Result = ServiceResult.define(:picture)

    # What is reported when a picture can't be saved again.
    class Unreadable < StandardError; end

    def self.call(upload)
      require "image_processing/vips" # libvips is needed only where pictures are kept (LabReports::Ocr does the same)
      return refused(:not_a_picture) unless upload.respond_to?(:path)
      return kept(upload) if upload.size > Message::MAX_IMAGE_SIZE

      type = Marcel::MimeType.for(Pathname.new(upload.path))
      return kept(upload) if type == "image/gif"
      return refused(:not_a_picture) unless FORMATS.key?(type)

      kept(io: saved_again(upload.path, type), filename: upload.original_filename, content_type: type)
    rescue LoadError, Vips::Error, ImageProcessing::Error => e
      # Vips names the upload's temporary file in its message, which would
      # make every picture a report of its own kind; the message goes in the
      # context instead.
      unreadable = Unreadable.new("#{e.class} on #{type || "a picture"}")
      Rails.error.report(unreadable, handled: true, context: { error: e.message })
      refused(:not_cleaned)
    end

    def self.saved_again(path, type)
      saver = type == "image/png" ? { strip: true } : { strip: true, quality: QUALITY }
      ImageProcessing::Vips.source(path).autorot.convert(FORMATS.fetch(type)).saver(**saver).call
    end

    def self.kept(picture) = Result.new(picture: picture, error: nil)
    def self.refused(error) = Result.new(picture: nil, error: error)
    private_class_method :saved_again, :kept, :refused
  end
end
