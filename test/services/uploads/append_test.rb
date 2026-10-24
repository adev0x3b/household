# frozen_string_literal: true

require "test_helper"

class Uploads::AppendTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @upload = Uploads::Create.call(owner: @alice, name: "clip.bin", byte_size: 10).upload
  end

  teardown { Uploads::Storage.delete(@upload.key) }

  test "chunks go on in order; a wrong offset is answered with the right one; the last one finishes the file" do
    result = Uploads::Append.call(@upload, io: StringIO.new("abcd"), offset: 0, length: 4)
    assert_predicate result, :success?
    assert_equal 4, result.offset
    assert_equal 4, @upload.reload.received_bytes

    repeat = Uploads::Append.call(@upload, io: StringIO.new("abcd"), offset: 0, length: 4)
    assert_equal :conflict, repeat.error
    assert_equal 4, repeat.offset
    assert_equal "abcd", File.read(@upload.path)

    assert_equal :too_large, Uploads::Append.call(@upload, io: StringIO.new("x" * 7), offset: 4, length: 7).error
    assert_equal :too_large, Uploads::Append.call(@upload, io: StringIO.new("x"), offset: 4, length: nil).error

    assert_enqueued_with(job: Uploads::FinishJob) do
      assert_predicate Uploads::Append.call(@upload, io: StringIO.new("efghij"), offset: 4, length: 6), :success?
    end
    assert_predicate @upload.reload, :processing?
    assert_equal :not_uploading, Uploads::Append.call(@upload, io: StringIO.new("k"), offset: 10, length: 1).error
    assert_equal "abcdefghij", File.read(@upload.path)
    assert_equal "600", "%o" % (File.stat(@upload.path).mode & 0o777)
  end

  test "the disk is right when the row disagrees with it" do
    Uploads::Storage.append(@upload.key, StringIO.new("abc"), at: 0)

    result = Uploads::Append.call(@upload, io: StringIO.new("zz"), offset: 0, length: 2)
    assert_equal :conflict, result.error
    assert_equal 3, result.offset
    assert_equal 3, @upload.reload.received_bytes
  end

  test "creating reserves the size against the household's quota" do
    with_env("FILES_QUOTA" => "1100") do
      assert_equal 74, Uploads::Quota.new(@alice.household).left # 1016 of the fixtures + 10 just made

      refused = Uploads::Create.call(owner: @alice, name: "big.bin", byte_size: 75)
      assert_equal :quota, refused.error
      assert_not refused.upload.persisted?
      assert_equal :too_large, Uploads::Create.call(owner: @alice, name: "huge.bin", byte_size: Upload::MAX_SIZE + 1).error
      assert_equal :invalid, Uploads::Create.call(owner: @alice, name: "nothing.bin", byte_size: 0).error
      assert_predicate Uploads::Create.call(owner: @alice, name: "fits.bin", byte_size: 74), :success?
    end
  end
end
