# frozen_string_literal: true

require "test_helper"

class UploadLinkTest < ActiveSupport::TestCase
  setup { @lease = uploads(:lease) }

  test "minted with a token the database only keeps a digest of" do
    link, token = mint_link(@lease)

    assert_predicate link, :persisted?
    assert_equal UploadLink.digest(token), link.token_digest
    assert_not_includes link.attributes.values, token
    assert_equal link, UploadLink.find_by_token(token)
    assert_nil UploadLink.find_by_token("not-it")
    assert_nil UploadLink.find_by_token(nil)
    assert_in_delta 7.days.from_now, link.expires_at, 5
    assert_equal 1, link.max_downloads
    assert_not link.protected?
    assert_equal :active, link.state
  end

  test "a lifetime of at most thirty days, a limit of a whole number, a password of eight or more" do
    link, _ = mint_link(@lease, lifetime_days: 31)
    assert_not link.persisted?
    assert link.errors.of_kind?(:expires_at, :too_far)

    link, _ = mint_link(@lease, lifetime_days: 30, max_downloads: nil, password: "seven77")
    assert_not link.persisted?
    assert link.errors.of_kind?(:password, :too_short)

    link, _ = mint_link(@lease, lifetime_days: 30, max_downloads: nil, password: "open sesame")
    assert_predicate link, :persisted?
    assert_predicate link, :protected?
    assert link.authenticate("open sesame")
    assert_not link.authenticate("wrong")
    assert_nil link.max_downloads
  end

  test "a link needs an expiry ahead of it; revoking twice keeps the first time" do
    link = UploadLink.new(upload: @lease, profile: @lease.profile, token_digest: "x", expires_at: nil)
    assert_not link.valid?
    assert_equal([ :blank ], link.errors.details[:expires_at].map { _1[:error] })
    link.expires_at = 1.minute.ago
    assert_not link.valid?
    assert link.errors.of_kind?(:expires_at, :past)

    link, _ = mint_link(@lease)
    link.revoke!
    revoked_at = link.revoked_at
    travel 1.hour do
      link.revoke!
      assert_equal revoked_at, link.reload.revoked_at
    end
  end

  test "ten wrong passwords close the link, and the trail says why" do
    link, _ = mint_link(@lease, password: "open sesame")
    request = ActionDispatch::TestRequest.create

    (UploadLink::MAX_WRONG_PASSWORDS - 1).times { link.refuse_password!(request:) }
    assert_not link.reload.revoked?

    link.refuse_password!(request:)
    assert_predicate link.reload, :revoked?
    assert_equal([ "link_locked", UploadLink::MAX_WRONG_PASSWORDS ], @lease.upload_activities.last.then { [ _1.action, _1.data["wrong_passwords"] ] })
  end

  test "consumed once per download, atomically; then spent, expired or revoked" do
    link, _ = mint_link(@lease, max_downloads: 2)

    assert link.consume!
    assert link.consume!
    assert_not link.consume!, "the third download is refused"
    assert_equal 2, link.reload.downloads_count
    assert_predicate link, :exhausted?
    assert_equal :exhausted, link.state
    assert_not link.usable?

    link, _ = mint_link(@lease, lifetime_days: 1)
    travel 2.days do
      assert_predicate link, :expired?
      assert_equal :expired, link.state
      assert_not link.consume!
    end

    link, _ = mint_link(@lease)
    link.revoke!
    assert_equal :revoked, link.state
    assert_not link.consume!
    assert_not link.continuation_allowed?
  end

  test "two presses at once: one gets the file" do
    link, _ = mint_link(@lease, max_downloads: 1)
    outcomes = Array.new(4) { Thread.new { UploadLink.find(link.id).consume! } }.map(&:value)

    assert_equal [ true ], outcomes.select(&:itself)
    assert_equal 1, link.reload.downloads_count
  end

  test "a download already started can go on for an hour, a revoked link's can't" do
    link, _ = mint_link(@lease)
    assert_not link.continuation_allowed?
    link.consume!
    assert_predicate link, :continuation_allowed?
    travel(2.hours) { assert_not link.reload.continuation_allowed? }
    link.revoke!
    assert_not link.continuation_allowed?
  end
end
