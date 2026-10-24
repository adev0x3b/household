# frozen_string_literal: true

require "test_helper"

# Platform: the admin's settings — the saved row first, then the
# environment. Secrets are encrypted; a blank field keeps the saved value.
class Platform::SettingTest < ActiveSupport::TestCase
  isolate_env "GOOGLE_BOOKS_API_KEY", "DEPLOY_DISPATCH_TOKEN", "DEMO_PASSWORD"

  test "until an admin saves, the environment decides, and the demo password has a default" do
    assert_nil Platform.google_books_api_key
    assert_nil Platform.deploy_dispatch_token
    assert_equal "demo-household", Platform.demo_password
    assert_nil Platform.source(:deploy_dispatch_token)

    ENV["GOOGLE_BOOKS_API_KEY"] = "gb-env"
    ENV["DEPLOY_DISPATCH_TOKEN"] = "tok-env"
    ENV["DEMO_PASSWORD"] = "env-password"
    assert_equal "gb-env", Platform.google_books_api_key
    assert_equal "tok-env", Platform.deploy_dispatch_token
    assert_equal "env-password", Platform.demo_password
    assert_equal :env, Platform.source(:deploy_dispatch_token)
  end

  test "a saved value wins over the environment; one never saved still comes from it" do
    ENV["GOOGLE_BOOKS_API_KEY"] = "gb-env"
    ENV["DEPLOY_DISPATCH_TOKEN"] = "tok-env"
    Platform::Setting.create!(deploy_dispatch_token: "tok-saved", updated_by: profiles(:alice))

    assert_equal "tok-saved", Platform.deploy_dispatch_token
    assert_equal :saved, Platform.source(:deploy_dispatch_token)
    assert_equal "aved", Platform.saved.hint(:deploy_dispatch_token)
    assert_equal "gb-env", Platform.google_books_api_key
    assert_equal :env, Platform.source(:google_books_api_key)
  end

  test "the row is read again after a save" do
    setting = Platform::Setting.create!(google_books_api_key: "gb-1", demo_password: "demo-secret-one")
    assert_equal "demo-secret-one", Platform.demo_password

    setting.update!(demo_password: "  demo-secret-two ")
    assert_equal "demo-secret-two", Platform.demo_password
  end

  test "a limit is a whole number, never below what it may be" do
    setting = Platform::Setting.new(assistant_messages_per_day: -1, book_lookups_per_day: 2.5, files_quota: 0, household_size: 0,
                                    invitations_per_member: 0)

    assert_not setting.valid?
    assert_equal %i[assistant_messages_per_day book_lookups_per_day files_quota household_size invitations_per_member],
                 setting.errors.attribute_names.sort
  end

  test "secrets are encrypted at rest, and the demo password follows Devise's rules" do
    setting = Platform::Setting.create!(deploy_dispatch_token: "tok-saved")
    assert_not_equal "tok-saved", setting.ciphertext_for(:deploy_dispatch_token)
    assert_equal "tok-saved", Platform::Setting.find(setting.id).deploy_dispatch_token

    assert_not setting.update(demo_password: "short")
    assert_predicate setting.errors[:demo_password], :any?
  end
end
