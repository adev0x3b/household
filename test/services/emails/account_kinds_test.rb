# frozen_string_literal: true

require "test_helper"

# The mail about an account, as a drain sends it: to whom, how often, and
# when it is no longer wanted.
class Emails::AccountKindsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  def drain = with_relay { relayed { Emails::Drain.call } }

  test "asked for twice before it went, a confirmation link goes once, to the address waiting, with a token made as it goes" do
    @alice.update!(unconfirmed_email: "alice@new.example")
    2.times { Emails::Enqueue.call(@alice, :email_confirmation) }

    mails = drain

    assert_equal [ [ "alice@new.example" ] ], mails.map(&:to)
    token = mails.sole.text_part.body.to_s[/token=([\w-]+)/, 1]
    assert_equal @alice, Profile.with_email_confirmation_token(token)
    assert_equal %w[sent sent], OutgoingEmail.pluck(:status)
  end

  test "a confirmation link no longer wanted, the address confirmed meanwhile, is dropped" do
    Emails::Enqueue.call(@alice, :email_confirmation)
    @alice.update!(email_confirmed_at: Time.current)

    assert_empty drain
    assert_predicate OutgoingEmail.sole, :dropped?
  end

  test "the notices of a new address go to the address confirmed before, which they no longer keep once sent" do
    Emails::Enqueue.call(@alice, :email_change_requested, data: { "to" => "alice@old.example" })

    assert_equal [ [ "alice@old.example" ] ], drain.map(&:to)
    assert_equal({}, OutgoingEmail.sole.data)
  end

  test "a forgotten password's link goes to the confirmed address, made as it goes, and works for half an hour from then" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)

    mail = drain.sole

    assert_equal [ "alice@example.com" ], mail.to
    token = mail.text_part.body.to_s[/reset_password_token=([\w-]+)/, 1]
    assert_equal @alice, Profile.with_reset_password_token(token)
    assert_in_delta Profile::SHORT_PASSWORD_LINK_FOR.from_now, @alice.reload.reset_password_expires_at, 1.second
  end

  test "a forgotten password's link is dropped once the person may no longer have one by mail, or was handed one since" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    @alice.admin!
    assert_empty drain

    @alice.user!
    Emails::Enqueue.call(@alice, :password_link)
    handed = @alice.password_link_token!
    assert_empty drain

    assert_equal %w[dropped dropped], OutgoingEmail.order(:id).pluck(:status)
    assert_equal @alice, Profile.with_reset_password_token(handed), "the link handed over still works"

    Emails::Enqueue.call(@alice, :password_link)
    printed = Profile.find(@alice.id).short_password_link_token!
    assert_empty drain

    assert_predicate OutgoingEmail.order(:id).last, :dropped?
    assert_equal @alice, Profile.with_reset_password_token(printed), "the link printed on the server still works"
  end

  test "a forgotten password's link that doesn't go out stops working" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    refused = ->(_mail) { raise Emails::Relay::Refused.new("The mail relay refused a message (550 5.1.1)", reply: "550 5.1.1 No such user") }

    assert_error_reported(Emails::Relay::Refused) { with_relay { relayed(answer: refused) { Emails::Drain.call } } }

    assert_predicate OutgoingEmail.sole, :failed?
    assert_nil @alice.reload.reset_password_token
  end

  test "a changed password is told to the address confirmed when it changed, even once another took over before it went" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    with_relay { Profiles::AfterPasswordChange.call(@alice) }
    @alice.update!(email: "alice@new.example", email_confirmed_at: Time.current)
    with_relay { Profiles::AfterPasswordChange.call(@alice) }

    assert_equal [ [ "alice@example.com" ], [ "alice@new.example" ] ], drain.map(&:to)
    assert_equal [ {} ], OutgoingEmail.distinct.pluck(:data), "no address kept once sent"
  end

  test "a forgotten password's link goes where the address is when it is made, and a change of address after ends it" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    rows = OutgoingEmail.includes(:profile).to_a
    Profile.find(@alice.id).update!(email: "alice@new.example", email_confirmed_at: Time.current)

    outgoing = @alice.as_viewer { Emails::Kinds::PasswordLink.new(rows).message }

    assert_equal [ "alice@new.example" ], outgoing.mail.to, "read again, not as the drain first loaded it"
    token = outgoing.mail.text_part.body.to_s[/reset_password_token=([\w-]+)/, 1]
    assert_equal @alice, Profile.with_reset_password_token(token)

    Profile.find(@alice.id).update!(email: "alice@newer.example", email_confirmed_at: Time.current)
    assert_nil Profile.with_reset_password_token(token)
  end

  test "a link the owner hands over while a mailed one is made wins, and keeps its two days" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    rows = OutgoingEmail.includes(:profile).to_a
    on_the_household_page = Profile.find(@alice.id)
    Profiles::PasswordLink.call(Profile.find(@alice.id), by: profiles(:bob))

    assert_nil @alice.as_viewer { Emails::Kinds::PasswordLink.new(rows).message }, "handed over since the row was read"

    rows = [ Emails::Enqueue.call(@alice, :password_link) ]
    @alice.as_viewer { Emails::Kinds::PasswordLink.new(rows).message }
    handed = Profiles::PasswordLink.call(on_the_household_page, by: profiles(:bob)).token
    assert_nil @alice.reload.reset_password_expires_at, "the mailed link's half hour isn't the handed one's"
    assert_equal @alice, Profile.with_reset_password_token(handed)
  end

  test "a forgotten password's link that waited for the relay until it was too late stops working, and another can be asked for" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)

    drain_unanswered
    assert_predicate @alice.reload.reset_password_token, :present?
    travel Emails::Kinds::PasswordLink.waits_at_most + 1.second
    assert_empty drain

    assert_predicate OutgoingEmail.sole, :failed?
    assert_nil @alice.reload.reset_password_token
    assert with_relay { Profiles::RequestPasswordLink.call(@alice) }, "nothing of the first is still out"
  end

  test "a forgotten password's link that waited for the relay goes once it can, and the link it carries works" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    drain_unanswered

    travel 3.minutes
    mail = drain.sole

    assert_predicate OutgoingEmail.sole, :sent?
    token = mail.text_part.body.to_s[/reset_password_token=([\w-]+)/, 1]
    assert_equal @alice, Profile.with_reset_password_token(token)
  end

  test "a link printed on the server while a mailed one waits for the relay wins: the mail makes none over it once it can go" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    drain_unanswered
    printed = Profile.find(@alice.id).short_password_link_token!

    travel 3.minutes
    assert_empty drain

    assert_predicate OutgoingEmail.sole, :dropped?
    assert_equal @alice, Profile.with_reset_password_token(printed)
  end

  test "a link printed on the server while a mailed one waits outlives the mail: one that can't go in time ends only its own" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    Emails::Enqueue.call(@alice, :password_link)
    drain_unanswered
    printed = Profile.find(@alice.id).short_password_link_token!

    travel Emails::Kinds::PasswordLink.waits_at_most + 1.second
    assert_empty drain

    assert_predicate OutgoingEmail.sole, :failed?
    assert_equal @alice, Profile.with_reset_password_token(printed)
  end

  test "a link to confirm an address whose mail didn't go out stops working, and the account page doesn't say it went" do
    Emails::Enqueue.call(@alice, :email_confirmation)
    refused = ->(_mail) { raise Emails::Relay::Refused.new("The mail relay refused a message (550 5.1.1)", reply: "550 5.1.1 No such user") }

    assert_error_reported(Emails::Relay::Refused) { with_relay { relayed(answer: refused) { Emails::Drain.call } } }

    assert_predicate OutgoingEmail.sole, :failed?
    assert_not @alice.reload.email_confirmation_open?
    assert_nil @alice.email_confirmation_digest
  end

  test "a link to confirm an address that waited for the relay until it was too late stops working, asked for again meanwhile or not" do
    Emails::Enqueue.call(@alice, :email_confirmation)
    drain_unanswered
    Emails::Enqueue.call(@alice, :email_confirmation)

    travel Emails::Kinds::EmailConfirmation.waits_at_most + 1.second
    assert_empty drain

    assert_equal %w[failed failed], OutgoingEmail.pluck(:status)
    assert_not @alice.reload.email_confirmation_open?
  end

  test "a link's mail for someone removed once it was claimed makes nothing, and ends without a fault" do
    @alice.update!(email_confirmed_at: 1.day.ago, unconfirmed_email: "alice@new.example")
    Emails::Enqueue.call(@alice, :password_link)
    Emails::Enqueue.call(@alice, :email_confirmation)
    claimed = [ Emails::Kinds::PasswordLink.new(OutgoingEmail.password_link.to_a),
                Emails::Kinds::EmailConfirmation.new(OutgoingEmail.email_confirmation.to_a) ]

    Profiles::Destroy.call(@alice)

    claimed.each do |kind|
      assert_nil kind.message, kind.class.key
      kind.ended
    end
  end

  private

  # A drain while the relay isn't answering: what it makes waits.
  def drain_unanswered
    down = ->(_mail) { raise Emails::Relay::Unavailable, "The mail relay isn't answering (ECONNREFUSED)" }
    assert_error_reported(Emails::Relay::Unavailable) { with_relay { relayed(answer: down) { Emails::Drain.call } } }
  end
end
