# frozen_string_literal: true

require "test_helper"

# The settings page's sections, saved together or not at all.
class Installation::SaveTest < ActiveSupport::TestCase
  test "every section is written on one row, by whoever saved it" do
    allowances = Installation::Allowances.current.assign(invitations: "0", assistant_messages_per_day: "", files_quota_amount: "8", files_quota_unit: "GB",
                                                         household_size: "12", invitations_per_member: "")
    books = Installation::Books.current.assign(google_books_api_key: " gb-key ", book_lookups_per_day: "20")

    result = Installation::Save.call([ allowances, books ], by: profiles(:alice))

    assert_predicate result, :success?
    setting = Platform::Setting.sole
    assert_equal [ false, nil, 8.gigabytes, 12, nil, "gb-key", 20 ],
                 [ setting.invitations, setting.assistant_messages_per_day, setting.files_quota, setting.household_size, setting.invitations_per_member,
                   setting.google_books_api_key, setting.book_lookups_per_day ]
    assert_equal profiles(:alice), setting.updated_by
  end

  test "one wrong section saves nothing, and every section says what was wrong" do
    allowances = Installation::Allowances.current.assign(files_quota_amount: "0", files_quota_unit: "GB")
    books = Installation::Books.current.assign(book_lookups_per_day: "-1")
    demo = Installation::DemoPassword.current.assign(demo_password: "short")

    result = Installation::Save.call([ allowances, books, demo ], by: profiles(:alice))

    assert_equal :invalid, result.error
    assert_not Platform::Setting.exists?
    assert allowances.errors.of_kind?(:files_quota_amount, :greater_than)
    assert books.errors.of_kind?(:book_lookups_per_day, :greater_than_or_equal_to)
    assert demo.errors.of_kind?(:demo_password, :too_short)
  end

  test "a blank secret keeps the saved one" do
    Platform::Setting.create!(deploy_dispatch_token: "tok-1")

    Installation::Save.call([ Installation::DeployToken.current.assign(deploy_dispatch_token: "  ") ], by: profiles(:alice))

    assert_equal "tok-1", Platform::Setting.sole.deploy_dispatch_token
  end
end
