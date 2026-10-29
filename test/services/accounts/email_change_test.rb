# frozen_string_literal: true

require "test_helper"

# Asking for another address with the password: it waits for its link
# where mail goes out, and takes over at once where none does.
class Accounts::EmailChangeTest < ActiveSupport::TestCase
  PASSWORD = "alice's long password"

  setup do
    @alice = profiles(:alice).tap { _1.update!(password: PASSWORD, password_confirmation: PASSWORD) }
  end

  def change(email: "alice@new.example", current_password: PASSWORD) = Accounts::EmailChange.new(@alice, email:, current_password:)

  test "where mail goes out, the new address waits for the link mailed to it, and the confirmed one hears of it" do
    @alice.update!(email_confirmed_at: 1.day.ago)

    assert(with_relay { change(email: " Alice@New.example ").save })

    @alice.reload
    assert_equal [ "alice@example.com", "alice@new.example" ], [ @alice.email, @alice.unconfirmed_email ]
    assert_predicate @alice, :email_confirmed?, "the address in use stays confirmed until the new one is"
    assert_equal %w[email_confirmation email_change_requested], OutgoingEmail.order(:id).pluck(:kind)
    assert_equal({ "to" => "alice@example.com" }, OutgoingEmail.email_change_requested.sole.data)
  end

  test "an address never confirmed hears nothing of a change: it may not be theirs" do
    with_relay { change.save }

    assert_equal %w[email_confirmation], OutgoingEmail.pluck(:kind)
  end

  test "where no mail goes out, the new address takes over at once, unconfirmed, and nothing is queued" do
    @alice.update!(email_confirmed_at: 1.day.ago, unconfirmed_email: "alice@waiting.example")

    assert change.save

    @alice.reload
    assert_equal "alice@new.example", @alice.email
    assert_nil @alice.unconfirmed_email
    assert_not @alice.email_confirmed?
    assert_not OutgoingEmail.exists?
  end

  test "a wrong password changes nothing, counts as a wrong sign-in, and says nothing of the address" do
    form = change(email: profiles(:bob).email, current_password: "a guess")

    assert_not(with_relay { form.save })
    assert_equal [ :current_password ], form.errors.attribute_names
    assert_equal 1, @alice.reload.failed_attempts
    assert_nil @alice.unconfirmed_email
  end

  test "an address someone else has is refused once the password is right; one's own, and one that isn't one or lists several, before" do
    taken = change(email: profiles(:bob).email.upcase)
    assert_not(with_relay { taken.save })
    assert taken.errors.of_kind?(:email, :taken)

    same = change(email: @alice.email)
    assert_not same.save
    assert same.errors.of_kind?(:email, :same)

    [ "alice at example", "alice@new.example,bob" ].each do |address|
      invalid = change(email: address)
      assert_not invalid.save
      assert invalid.errors.of_kind?(:email, :invalid), address
    end
    assert_equal 0, @alice.reload.failed_attempts, "a form refused before its password tries nothing"
  end

  test "three links a day: the fourth ask is refused and mails nothing" do
    with_relay do
      3.times { |n| assert change(email: "alice#{n}@new.example").save }
      fourth = change(email: "alice3@new.example")

      assert_not fourth.save
      assert fourth.errors.of_kind?(:base, :no_links_left)
    end
    assert_equal "alice2@new.example", @alice.reload.unconfirmed_email
    assert_equal 3, OutgoingEmail.email_confirmation.count

    travel 1.day + 1.second
    assert(with_relay { change(email: "alice3@new.example").save })
  end
end
