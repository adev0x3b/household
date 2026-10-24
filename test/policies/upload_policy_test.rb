# frozen_string_literal: true

require "test_helper"

class UploadPolicyTest < ActiveSupport::TestCase
  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @photo = Upload.includes(:upload_shares).find(uploads(:photo).id) # bob's, shared with alice
    @backup = Upload.includes(:upload_shares).find(uploads(:backup).id) # alice's, still coming
  end

  test "the owner does everything, a sharee sees and downloads, the rest nothing" do
    assert_predicate UploadPolicy.new(@bob, @photo), :update?
    assert_predicate UploadPolicy.new(@bob, @photo), :link?
    assert_predicate UploadPolicy.new(@bob, @photo), :download?
    assert_predicate UploadPolicy.new(@bob, @photo), :chunk?

    alice = UploadPolicy.new(@alice, @photo)
    assert_predicate alice, :show?
    assert_predicate alice, :download?
    assert_not alice.update?
    assert_not alice.link?
    assert_not alice.destroy?
    assert_not alice.chunk?

    assert_not UploadPolicy.new(@carol, @photo).show?
  end

  test "a file still coming is seen by its owner alone, and not yet linked or downloaded" do
    owner = UploadPolicy.new(@alice, @backup)
    assert_predicate owner, :show?
    assert_predicate owner, :chunk?
    assert_predicate owner, :progress?
    assert_not owner.download?
    assert_not owner.link?
  end

  test "with uploads off, nothing new comes in and no public link goes out; what is there is seen and downloaded" do
    file = keep_file(@alice, name: "kept.txt")

    with_env("UPLOADS" => "off") do
      policy = UploadPolicy.new(@alice, file)
      assert_not policy.create?
      assert_not policy.link?
      assert_predicate policy, :update?
      assert_predicate policy, :show?
      assert_predicate policy, :download?
    end
    assert_predicate UploadPolicy.new(@alice, file), :create?
    assert_predicate UploadPolicy.new(@alice, file), :link?
  end

  test "a file's public links are reached by its owner alone, even by someone it is shared with" do
    link, _token = mint_link(@photo)

    assert_equal [ link ], UploadLinkPolicy::Scope.new(@bob, UploadLink).resolve.to_a
    assert_empty UploadLinkPolicy::Scope.new(@alice, UploadLink).resolve
  end
end
