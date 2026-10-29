# frozen_string_literal: true

require "test_helper"

# /admin/settings: the admin sets what the installation allows, the Google
# Books key and budget, the deploy token and the demo password; a secret
# never comes back; nobody else gets in.
class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password"

  isolate_env "GOOGLE_BOOKS_API_KEY", "DEPLOY_DISPATCH_TOKEN", "DEMO_PASSWORD", "KAMAL_DESTINATION"

  # The form's params, a section at a time: { books: { … } } and the password.
  def settings(password: PASSWORD, **sections) = { settings: { password: password }.compact.merge(sections) }

  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin, password: PASSWORD, password_confirmation: PASSWORD) }
    sign_in @admin
  end

  test "a member who isn't an admin is turned away, and sees no link" do
    sign_in profiles(:bob)

    get admin_settings_path
    assert_redirected_to root_path
    patch admin_settings_path, params: settings(deploy_token: { deploy_dispatch_token: "tok" })
    assert_redirected_to root_path
    delete value_admin_settings_path("deploy_dispatch_token")
    assert_redirected_to root_path
    assert_not Platform::Setting.exists?

    get root_path
    assert_select "a.navbar-link[href=?]", admin_settings_path, count: 0
  end

  test "the page says where each value comes from and never shows a secret" do
    ENV["GOOGLE_BOOKS_API_KEY"] = "gb-env"
    Platform::Setting.create!(deploy_dispatch_token: "tok-saved")

    get admin_settings_path
    assert_response :success
    assert_select "a.navbar-link[href=?]", admin_settings_path
    assert_select "input[type=password][name='settings[books][google_books_api_key]'][value=''][placeholder*='GOOGLE_BOOKS_API_KEY']"
    assert_select "input[type=password][name='settings[deploy_token][deploy_dispatch_token]'][value=''][placeholder*='aved']"
    assert_select "input[type=password][name='settings[demo_password][demo_password]'][placeholder*='demo-household']"
    assert_select "a[href=?][data-turbo-method=delete]", value_admin_settings_path("deploy_dispatch_token")
    assert_select "a[href=?][data-turbo-method=delete]", value_admin_settings_path("google_books_api_key"), count: 0
    assert_select ".notice a[href=?]", assistant_settings_path
    assert_no_match "tok-saved", response.body
  end

  test "saving keeps what was left blank, and the deployment page gets its console from the saved token" do
    Platform::Setting.create!(google_books_api_key: "gb-1")

    get admin_deployment_path
    assert_select ".notice a[href=?]", admin_settings_path
    assert_select "turbo-frame##{Views::Admin::Deliveries::Console::FRAME_ID}", count: 0
    assert_select ".page-controls a[href*=freeze]", count: 0

    swapping(Delivery::Github, :check, -> { { actions: true, contents: true, deployments: true, pull_requests: true, variables: true } }) do
      patch admin_settings_path, params: settings(books: { google_books_api_key: "" }, deploy_token: { deploy_dispatch_token: " tok-2 " },
                                                  demo_password: { demo_password: "" })
    end
    assert_redirected_to admin_settings_path
    assert_match(/saved/i, flash[:success])
    assert_nil flash[:alert]

    setting = Platform::Setting.sole
    assert_equal "gb-1", setting.google_books_api_key
    assert_equal "tok-2", setting.deploy_dispatch_token
    assert_nil setting.demo_password
    assert_equal @admin, setting.updated_by

    swapping(Delivery::Github, :frozen?, -> { false }) { get admin_deployment_path }
    assert_select "turbo-frame##{Views::Admin::Deliveries::Console::FRAME_ID}[src=?]", console_admin_delivery_path
    assert_select ".page-controls a[href=?]", new_admin_delivery_request_path(kind: :freeze)
    assert_select ".notice", count: 0
  end

  test "a token that can't read everything the Deployment page needs is saved, and told what it lacks" do
    checked = false
    swapping(Delivery::Github, :check, -> { checked = true; { actions: true, contents: "GitHub answered 403: Resource not accessible", deployments: true, variables: "GitHub answered 403: Resource not accessible" } }) do
      patch admin_settings_path, params: settings(deploy_token: { deploy_dispatch_token: "tok-3" })
    end

    assert checked
    assert_equal "tok-3", Platform::Setting.sole.deploy_dispatch_token
    assert_match(/saved/i, flash[:success])
    assert_match(/can't read the commits \(Contents: read\) \(GitHub answered 403.*\) and the freeze \(Variables: read\)/, flash[:alert])
    assert_match(/example\/household/, flash[:alert])

    # Saving something else doesn't try the token.
    swapping(Delivery::Github, :check, -> { flunk "checked" }) do
      patch admin_settings_path, params: settings(demo_password: { demo_password: "a-long-enough-one" })
    end
    assert_redirected_to admin_settings_path
  end

  test "the page says when the token expires, and warns when that is near or past" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    get admin_settings_path
    assert_select ".admin-settings__expiry", count: 0

    Rails.cache.write(Delivery::Github::EXPIRY_KEY, 60.days.from_now)
    get admin_settings_path
    assert_select ".admin-settings__expiry:not(.is-warning):not(.is-danger)", text: /Expires on/

    Rails.cache.write(Delivery::Github::EXPIRY_KEY, 5.days.from_now)
    get admin_settings_path
    assert_select ".admin-settings__expiry.is-warning", text: /Expires in 5 days/

    Rails.cache.write(Delivery::Github::EXPIRY_KEY, 1.day.ago)
    get admin_settings_path
    assert_select ".admin-settings__expiry.is-danger", text: /Expired on/
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end

  test "a demo password too short is refused, with the page back" do
    patch admin_settings_path, params: settings(demo_password: { demo_password: "abc" })

    assert_response :unprocessable_content
    assert_select ".notice--critical", text: /Demo password/
    assert_select ".field.is-invalid input[name='settings[demo_password][demo_password]'][aria-invalid=true][value='']"
    assert_not Platform::Setting.exists?
  end

  test "forgetting a saved value hands over to the environment" do
    ENV["DEPLOY_DISPATCH_TOKEN"] = "tok-env"
    Platform::Setting.create!(deploy_dispatch_token: "tok-saved", google_books_api_key: "gb-1")

    delete value_admin_settings_path("deploy_dispatch_token")
    assert_redirected_to admin_settings_path
    assert_match(/forgotten/, flash[:success])

    setting = Platform::Setting.sole
    assert_nil setting.deploy_dispatch_token
    assert_equal "gb-1", setting.google_books_api_key
    assert_equal @admin, setting.updated_by
    assert_equal "tok-env", Platform.deploy_dispatch_token
  end

  test "a save waits for the admin's password: a wrong one saves nothing and counts, the right one holds a while" do
    get admin_settings_path
    assert_select "input[type=password][name='settings[password]'][autocomplete=current-password]:not([required])"

    patch admin_settings_path, params: settings(password: nil, deploy_token: { deploy_dispatch_token: "tok-stolen" })
    assert_response :unprocessable_content
    assert_select ".notice--critical", text: /isn't your password/
    patch admin_settings_path, params: settings(password: "a guess", deploy_token: { deploy_dispatch_token: "tok-stolen" })
    assert_response :unprocessable_content
    assert_not Platform::Setting.exists?
    assert_equal 1, @admin.reload.failed_attempts, "the guess counts, the blank doesn't"

    patch admin_settings_path, params: settings(demo_password: { demo_password: "a-long-enough-one" })
    assert_redirected_to admin_settings_path
    follow_redirect!
    assert_select "input[name='settings[password]']", count: 0

    patch admin_settings_path, params: settings(password: nil, demo_password: { demo_password: "another-long-one" })
    assert_redirected_to admin_settings_path
    assert_equal "another-long-one", Platform::Setting.sole.demo_password
  end

  test "what the installation allows is saved from its card, and decides at once" do
    patch admin_settings_path, params: settings(allowances: { uploads: "0", pictures: "1", assistant_messages_per_day: "12", files_quota_amount: "3", files_quota_unit: "GB",
                                                              household_size: "10", invitations_per_member: "3" },
                                                books: { book_lookups_per_day: "" })

    assert_redirected_to admin_settings_path
    assert_not Platform.uploads?
    assert_predicate Platform, :pictures?
    assert_equal 12, Platform.assistant_messages_per_day
    assert_nil Platform.book_lookups_per_day
    assert_equal 3.gigabytes, Platform.files_quota
    assert_equal [ 10, 3 ], [ Platform.household_size, Platform.invitations_per_member ]

    follow_redirect!
    assert_select "input[type=checkbox][name='settings[allowances][uploads]']:not([checked])"
    assert_select "input[type=checkbox][name='settings[allowances][pictures]'][checked]"
    assert_select "input[name='settings[allowances][files_quota_amount]'][value='3']"
    assert_select "select[name='settings[allowances][files_quota_unit]'] option[selected][value='GB']"
  end

  test "a limit the environment names only starts there: the admin changes it, and what they saved stays" do
    with_env("UPLOADS" => "off", "FILES_QUOTA" => "512MB", "HOUSEHOLD_SIZE" => "4") do
      get admin_settings_path
      assert_select "input[disabled]", count: 0
      assert_select "input[name='settings[allowances][household_size]'][value='4']"
      assert_select "input[type=checkbox][name='settings[allowances][uploads]']:not([checked])"
      assert_select "input[name='settings[allowances][files_quota_amount]'][value='512']"
      assert_select "select[name='settings[allowances][files_quota_unit]'] option[selected][value='MB']"

      patch admin_settings_path, params: settings(allowances: { uploads: "1", files_quota_amount: "9", files_quota_unit: "GB", household_size: "" })
      assert_redirected_to admin_settings_path
      assert_predicate Platform, :uploads?
      assert_nil Platform.household_size
      assert_equal 9.gigabytes, Platform.files_quota
    end
  end

  test "the mail card shows where each of the relay's values comes from, and never its password" do
    Platform::Setting.create!(smtp_password: "relay-secret")

    with_relay("SMTP_TLS" => "tls") { get admin_settings_path }
    assert_response :success
    assert_select "input[name='settings[mail][smtp_host]']:not([value])[placeholder='relay.example (from SMTP_HOST)']"
    assert_select "input[name='settings[mail][smtp_username]']:not([value])[placeholder='household (from SMTP_USERNAME)']"
    assert_select "input[name='settings[mail][mail_from]'][placeholder='household@household.example (from MAIL_FROM)']"
    assert_select "select[name='settings[mail][smtp_tls]'] option[value='']", text: "tls (from SMTP_TLS)"
    assert_select "input[type=password][name='settings[mail][smtp_password]'][value=''][placeholder='Saved']"
    assert_select "a[href=?][data-turbo-method=delete]", value_admin_settings_path("smtp_password")
    assert_select "input[name='settings[mail][mails_per_hour]'][value='6'][min='2']"
    assert_no_match "relay-secret", response.body

    get admin_settings_path
    assert_select "input[name='settings[mail][smtp_port]'][placeholder=?]", "The encryption's usual port (the default)"
    assert_select "input[name='settings[mail][mail_from]'][placeholder='Not set: nothing is mailed']"
  end

  test "a relay saved on the card takes no login from the environment, and the card doesn't offer one" do
    Platform::Setting.create!(smtp_host: "saved.example")

    with_relay { get admin_settings_path }

    assert_select "input[name='settings[mail][smtp_host]'][value='saved.example']"
    assert_select "input[name='settings[mail][smtp_username]']:not([value])[placeholder='None']"
    assert_select "input[type=password][name='settings[mail][smtp_password]'][placeholder='Not set: needed only when the relay asks for a login']"
    assert_select "a[href=?]", value_admin_settings_path("smtp_password"), count: 0
  end

  test "the relay and mail's budgets are saved from their card, a blank password keeps the saved one" do
    Platform::Setting.create!(smtp_password: "relay-secret")

    patch admin_settings_path, params: settings(mail: { outgoing_mail: "1", smtp_host: " relay.example ", smtp_port: "465", smtp_tls: "tls",
                                                        smtp_username: "household", smtp_password: "", mail_from: "household@household.example",
                                                        mails_per_hour: "10", mails_per_day: "", reminder_mails_per_day: "0" })

    assert_redirected_to admin_settings_path
    setting = Platform::Setting.sole
    assert_equal [ "relay.example", 465, "tls", "household", "relay-secret", "household@household.example" ],
                 [ setting.smtp_host, setting.smtp_port, setting.smtp_tls, setting.smtp_username, setting.smtp_password, setting.mail_from ]
    assert_equal [ true, 10, nil, 0 ], [ setting.outgoing_mail, setting.mails_per_hour, setting.mails_per_day, setting.reminder_mails_per_day ]

    patch admin_settings_path, params: settings(mail: { outgoing_mail: "0" })
    delete value_admin_settings_path("smtp_password")
    assert_match(/Mail relay password/, flash[:success])

    relay = Emails::RelaySettings.current
    assert_equal [ "relay.example", nil ], [ relay.host, relay.password ]
    assert_equal [ 10, 40, 0 ], [ Platform.mails_per_hour, Platform.mails_per_day, Platform.reminder_mails_per_day ], "an empty budget is its default"
    assert_not_predicate Emails, :enabled?
  end

  test "a relay that can't be one, or a budget under its least, is refused with the fields marked" do
    patch admin_settings_path, params: settings(mail: { smtp_host: "https://relay.example", smtp_port: "smtp", mail_from: "household", mails_per_hour: "1" })

    assert_response :unprocessable_content
    assert_select ".notice--critical", text: /Relay server/
    %w[smtp_host smtp_port mail_from mails_per_hour].each do |name|
      assert_select ".field.is-invalid input[name='settings[mail][#{name}]'][aria-invalid=true]"
    end
    assert_not Platform::Setting.exists?
  end

  test "a limit that isn't a whole number in range is refused, and nothing is saved" do
    patch admin_settings_path, params: settings(allowances: { assistant_messages_per_day: "-2", files_quota_amount: "0", files_quota_unit: "GB", household_size: "0",
                                                              invitations_per_member: "0" })

    assert_response :unprocessable_content
    assert_select ".notice--critical", text: /Assistant messages per household/
    assert_select ".field.is-invalid input[name='settings[allowances][household_size]'][aria-invalid=true]"
    assert_select ".field.is-invalid input[name='settings[allowances][invitations_per_member]'][aria-invalid=true]"
    assert_select ".field.is-invalid input[name='settings[allowances][files_quota_amount]'][aria-invalid=true]"
    assert_not Platform::Setting.exists?
  end
end
