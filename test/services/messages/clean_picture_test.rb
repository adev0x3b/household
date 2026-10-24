# frozen_string_literal: true

require "test_helper"
require "vips"

# A picture sent in a message keeps the picture, not where it was taken.
class Messages::CleanPictureTest < ActiveSupport::TestCase
  test "turned the way the camera held it, then saved without its metadata: the place, the phone" do
    clean = Messages::CleanPicture.call(photo(orientation: 6, make: "SpyCam", latitude_ref: "N")).picture
    image = Vips::Image.new_from_buffer(clean[:io].read, "")

    assert_equal [ 20, 40 ], [ image.width, image.height ], "turned upright: orientation 6 is a quarter turn"
    assert_empty image.get_fields.grep(/exif|xmp|iptc|orientation/), "no metadata left"
    assert_equal [ "photo.jpg", "image/jpeg" ], clean.values_at(:filename, :content_type)
  end

  test "a photo is known by its bytes: one sent as a GIF is cleaned all the same" do
    jpeg = photo(orientation: 1, make: "SpyCam", latitude_ref: "N")
    disguised = upload(File.binread(jpeg.path), "image/gif", "photo.gif")

    clean = Messages::CleanPicture.call(disguised).picture
    image = Vips::Image.new_from_buffer(clean[:io].read, "")

    assert_equal "image/jpeg", clean[:content_type]
    assert_empty image.get_fields.grep(/exif|xmp|iptc/), "no metadata left"
  end

  test "a GIF goes on as it came: saving it again would lose its animation" do
    gif = upload("GIF89a", "image/gif", "wave.gif")

    assert_same gif, Messages::CleanPicture.call(gif).picture
  end

  test "what isn't a picture is refused as such" do
    text = upload("not a picture", "image/jpeg", "lie.jpg")

    assert_equal :not_a_picture, Messages::CleanPicture.call(text).error
    assert_equal :not_a_picture, Messages::CleanPicture.call("a string").error
  end

  test "a picture that can't be saved again is refused, never kept with its metadata, and reported" do
    broken = upload("\xFF\xD8\xFF\xE0 then nothing a JPEG holds".b, "image/jpeg", "broken.jpg")

    result = nil
    assert_error_reported(Messages::CleanPicture::Unreadable) { result = Messages::CleanPicture.call(broken) }

    assert_equal :not_cleaned, result.error
    assert_nil result.picture
  end

  private

  def photo(orientation:, make:, latitude_ref:)
    image = Vips::Image.black(40, 20, bands: 3).copy
    image.set_type(GObject::GINT_TYPE, "orientation", orientation)
    image.set_type(GObject::GSTR_TYPE, "exif-ifd0-Make", make)
    image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitudeRef", latitude_ref)
    upload(image.write_to_buffer(".jpg"), "image/jpeg", "photo.jpg")
  end

  # As a form's file arrives: in a tempfile on disk.
  def upload(bytes, type, name)
    file = Tempfile.new([ "upload", File.extname(name) ], binmode: true).tap { _1.write(bytes) && _1.rewind }
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
  end
end
