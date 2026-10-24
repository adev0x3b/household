# frozen_string_literal: true

require "test_helper"

# Setup::Complete: the whole first setup saved at once, or nothing.
class Setup::CompleteTest < ActiveSupport::TestCase
  setup do
    Household.find_each { |household| Households::Destroy.call(household) }
  end

  def form(**steps)
    Setup::Form.new({
      account: { first_name: "Alex", username: "ops", email: "ops@example.com", password: "a-long-password",
                 password_confirmation: "a-long-password", locale: "en" },
      household: { name: "Casa Nuova", currency: "EUR" },
      allowances: { assistant: "1", uploads: "1", pictures: "1", invitations: "1", push_notifications: "1", release_check: "0",
                    files_quota_amount: "50", files_quota_unit: "GB" },
      assistant: { provider: "ollama", model: "qwen3:8b", ollama_url: "http://localhost:11434" },
      books: {},
      housemates: {}
    }.deep_merge(steps))
  end

  test "makes the household, its admin, the settings, the assistant's model and every invitation" do
    result = Setup::Complete.call(form(housemates: { people: { "0" => { first_name: "Sam", email: "sam@example.com" },
                                                               "1" => { email: "robin@example.com" } } }))

    assert_predicate result, :success?
    household = result.profile.household
    assert_equal result.profile, household.owner
    assert_equal(%w[sam@example.com robin@example.com], result.invitations.map { |invitation| invitation.profile.email })
    assert(result.invitations.all? { |invitation| invitation.token.present? })
    assert_equal "Sam", household.invitations.find_by!(email: "sam@example.com").first_name
    assert_equal result.profile, Platform::Setting.first.updated_by
    assert_not Platform.release_check?
    assert_equal [ "ollama", result.profile ], [ Assistant::Setting.saved.provider, Assistant::Setting.saved.updated_by ]
  end

  test "a step with something wrong saves nothing, and each step keeps its own errors" do
    setup_form = form(household: { name: "" }, allowances: { files_quota_amount: "0", files_quota_unit: "GB" })

    assert_no_difference [ -> { Household.count }, -> { Profile.count }, -> { Platform::Setting.count } ] do
      assert_predicate Setup::Complete.call(setup_form), :failure?
    end
    assert_predicate setup_form.step(Setup::HouseholdDetails).errors[:name], :any?
    assert_predicate setup_form.step(Installation::Allowances).errors[:files_quota_amount], :any?
    assert_equal setup_form.step(Setup::HouseholdDetails), setup_form.first_invalid
  end

  test "an invitation refused at the last moment undoes the whole setup" do
    swapping(Households::Invite, :call, ->(*, **) { Households::Invite::Result.new(profile: Profile.new.tap { _1.errors.add(:base, :household_full, max: 1) }, token: nil, error: :household_full) }) do
      assert_no_difference [ -> { Household.count }, -> { Profile.count }, -> { Platform::Setting.count } ] do
        assert_predicate Setup::Complete.call(form(housemates: { people: { "0" => { email: "sam@example.com" } } })), :failure?
      end
    end
  end

  test "a copy someone set up a moment ago is refused, on the account step" do
    Admins::Create.call(household_name: "First", username: "first", email: "first@example.com", password: "a-long-password")
    setup_form = form

    assert_no_difference -> { Household.count } do
      assert_predicate Setup::Complete.call(setup_form), :failure?
    end
    assert_predicate setup_form.step(Setup::Account).errors[:base], :any?
  end
end
