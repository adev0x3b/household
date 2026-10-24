# frozen_string_literal: true

require "test_helper"

# Setup::Form: every step of the first setup in one form.
class Setup::FormTest < ActiveSupport::TestCase
  test "starts from the defaults: the page's language, the household's currency, every switch the installation has" do
    form = I18n.with_locale(:it) { Setup::Form.new }

    assert_equal "it", form.step(Setup::Account).locale
    assert_equal "EUR", form.step(Setup::HouseholdDetails).currency
    assert form.step(Installation::Allowances).uploads
    assert_empty form.step(Setup::Housemates).people
  end

  test "the assistant's step is asked only while the installation allows the assistant" do
    assert_includes Setup::Form.new(allowances: { assistant: "1" }).asked.map(&:class), Installation::Assistant
    assert_not_includes Setup::Form.new(allowances: { assistant: "0" }).asked.map(&:class), Installation::Assistant
  end

  test "housemates: empty rows are nobody; a repeated email and the account's own are refused" do
    form = Setup::Form.new(account: { email: "ops@example.com" },
                           housemates: { people: { "0" => { email: "" }, "1" => { email: "OPS@example.com" },
                                                   "2" => { email: "sam@example.com" }, "3" => { email: "sam@example.com" } } })
    housemates = form.step(Setup::Housemates)

    assert_not housemates.valid?
    assert_equal 3, housemates.people.size
    assert_equal([ [ :owner ], [], [ :repeated ] ], housemates.people.map { |person| person.errors.details[:email].pluck(:error) })
  end

  test "housemates: as many as the limits typed on the same form allow, the account taking one of the household's places" do
    crowd = (1..6).to_h { |index| [ index.to_s, { email: "person#{index}@example.com" } ] }
    housemates = ->(allowances) { Setup::Form.new(allowances:, housemates: { people: crowd }).step(Setup::Housemates) }

    assert_predicate housemates.call(household_size: "", invitations_per_member: ""), :valid?, "no limit"
    assert_predicate housemates.call(household_size: "7", invitations_per_member: "6"), :valid?

    [ { household_size: "6" }, { invitations_per_member: "5" } ].each do |limits|
      too_many = housemates.call(limits)
      assert_not too_many.valid?, limits
      assert_equal [ 5 ], too_many.errors.where(:people, :too_many).map { _1.options[:count] }, limits
    end
  end

  test "the account and the household are checked by the rules of the records they become" do
    form = Setup::Form.new(account: { username: "ops@example.com", email: "ops@example.com", password: "short", password_confirmation: "short" },
                           household: { name: "!!!", currency: "EURO" })

    assert_not form.valid?
    assert_predicate form.step(Setup::Account).errors[:password], :any?
    assert_predicate form.step(Setup::HouseholdDetails).errors[:name], :any?, "a name no address can be made from"
    assert_predicate form.step(Setup::HouseholdDetails).errors[:currency], :any?
  end
end
