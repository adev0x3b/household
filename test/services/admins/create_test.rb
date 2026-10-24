# frozen_string_literal: true

require "test_helper"

# Admins::Create: the first household and its admin, both or neither.
class Admins::CreateTest < ActiveSupport::TestCase
  def create(**overrides)
    Admins::Create.call(**{ household_name: "Casa Ops", username: "ops", email: "ops@example.com",
                            password: "a-long-password", password_confirmation: "a-long-password" }.merge(overrides))
  end

  test "makes the household, owned by its admin, who can sign in" do
    result = nil
    assert_difference [ -> { Household.count }, -> { Profile.admin.count } ], 1 do
      result = create
    end

    assert_predicate result, :success?
    profile = result.profile
    assert_predicate profile, :persisted?
    assert_predicate profile, :admin?
    assert_equal profile, profile.household.owner
    assert_equal "Casa Ops", profile.household.name
    assert profile.valid_password?("a-long-password")
    assert_not profile.invitation_pending?
    assert_predicate profile.analytes, :exists?, "the standard analytes are seeded, as for anyone who joins"
  end

  test "nothing is made when something is wrong, and every reason is given at once" do
    result = nil
    assert_no_difference [ -> { Household.count }, -> { Profile.count } ] do
      result = create(household_name: " ", username: profiles(:alice).username, password_confirmation: "other")
    end

    assert_equal :invalid, result.error
    profile = result.profile
    assert_not profile.persisted?
    assert profile.errors.of_kind?(:"household.name", :blank)
    assert_predicate profile.errors[:username], :any?
    assert_predicate profile.errors[:password_confirmation], :any?
  end

  test "a household name already taken is refused" do
    result = create(household_name: households(:example).name)
    profile = result.profile

    assert_predicate result, :failure?
    assert_not profile.persisted?
    assert profile.errors.of_kind?(:"household.slug", :taken)
    assert_not Profile.exists?(username: "ops")
  end

  test "the setup page's first account only while nobody exists, decided under a lock" do
    assert_predicate Profile, :exists?

    result = nil
    assert_no_difference [ -> { Household.count }, -> { Profile.count } ] do
      result = create(first: true)
    end
    assert result.profile.errors.of_kind?(:base, :already_set_up)

    assert_predicate create, :success?, "the rake tasks make one on a database that has people"
  end
end
