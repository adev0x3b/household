# frozen_string_literal: true

require "test_helper"

class Households::CreateTest < ActiveSupport::TestCase
  test "a household is born with its first member's invitation, who owns it" do
    result = create(name: "Casa Verdi", email: "anna@example.com", first_name: "Anna")

    assert_predicate result, :success?
    first = result.invitation.profile
    assert_equal [ result.household, "Anna", true ], [ first.household, first.first_name, first.invitation_pending? ]
    assert_equal first, result.household.reload.owner
  end

  test "an invitation refused takes the household with it, and its errors are the household's" do
    assert_no_difference -> { Household.count } do
      taken = create(name: "Casa Bianchi", email: profiles(:bob).email)
      assert_equal [ :invalid, nil ], [ taken.error, taken.invitation ]
      assert_not taken.household.persisted?
      assert taken.household.errors.of_kind?(:first_member_email, :taken)
      assert_equal profiles(:bob).email, taken.household.first_member_email, "the form shows what was typed"

      nameless = create(name: "", email: "new@example.com")
      assert_predicate nameless, :failure?
      assert nameless.household.errors.of_kind?(:name, :blank)
    end
    assert_not Profile.exists?(email: "new@example.com")
  end

  private

  def create(**fields) = Households::Create.call(inviter: profiles(:alice), **fields)
end
