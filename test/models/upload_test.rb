# frozen_string_literal: true

require "test_helper"

class UploadTest < ActiveSupport::TestCase
  test "one's own files and the ones shared with one, nobody else's" do
    alice, bob, carol = profiles(:alice), profiles(:bob), profiles(:carol)

    assert_equal [ uploads(:backup), uploads(:lease), uploads(:photo) ].map(&:id).sort, Upload.accessible_by(alice).pluck(:id).sort
    assert_equal [ uploads(:photo) ], Upload.accessible_by(bob).to_a
    assert_empty Upload.accessible_by(carol)
    assert_empty Upload.accessible_by(profiles(:outsider))
  end

  test "the name is cleaned, never a path or a hidden file, and cut keeping its extension" do
    upload = Upload.new(profile: profiles(:alice), byte_size: 1)

    upload.name = "  ../../etc/passwd "
    assert_equal "etc passwd", upload.name
    upload.name = ".hidden\u0000file.txt"
    assert_equal "hidden file.txt", upload.name
    upload.name = "#{"a" * 300}.pdf"
    assert_equal 255, upload.name.length
    assert upload.name.end_with?(".pdf")
    upload.name = "///"
    assert_equal "file", upload.name
  end

  test "a key is made, the size is bounded, the kind follows the type" do
    upload = Upload.new(profile: profiles(:alice), name: "x.bin", byte_size: 0)
    assert_not upload.valid?
    upload.byte_size = Upload::MAX_SIZE + 1
    assert_not upload.valid?
    upload.byte_size = 1
    assert_predicate upload, :valid?
    assert_match(/\A[0-9a-f-]{36}\z/, upload.key)
    upload.key = "../../config/master.key"
    assert upload.errors.of_kind?(:key, :invalid) unless upload.valid?
    assert_not upload.valid?, "a key is a UUID: it is all a path on disk is made of"

    assert_equal :pdf, uploads(:lease).kind
    assert_equal :image, uploads(:photo).kind
    assert_equal :archive, uploads(:backup).kind
    assert_equal :file, Upload.new.kind
    assert_equal "GZ", uploads(:backup).extension
  end

  test "the storage builds a path from a key and nothing else" do
    assert_equal "ab", Uploads::Storage.path("ab12cdef-1234-4321-abcd-0123456789ab").dirname.dirname.basename.to_s
    [ "../../config/master.key", "", nil, "ab12cdef-1234-4321-abcd-0123456789ab/../x" ].each do |key|
      assert_raises(ArgumentError, key.inspect) { Uploads::Storage.path(key) }
    end
  end

  test "an upload untouched for a day is abandoned" do
    assert_empty Upload.abandoned
    uploads(:backup).update_columns(updated_at: 25.hours.ago)
    assert_equal [ uploads(:backup) ], Upload.abandoned.to_a
  end
end
