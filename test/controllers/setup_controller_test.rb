# frozen_string_literal: true

require "test_helper"

# /setup: on an empty database every visitor lands there and the first setup
# is made at once (Setup::Complete): a household, its admin, what the
# installation allows, the assistant's model and the invitations. Once anyone
# exists it's gone.
class SetupControllerTest < ActionDispatch::IntegrationTest
  # Every household removed with all it holds, so the page is tested against a
  # database that really holds nobody.
  def with_empty_database
    Household.find_each { |household| Households::Destroy.call(household) }
    yield
  end

  # A code made as the installer would, and given by this browser.
  def give_the_setup_code
    code = SetupCodes::Renew.call.code
    post setup_code_path, params: { setup_code: { code: code } }
    code
  end

  # Every step answered, as a person pressing Next through the defaults
  # would send it, with what a test changes merged in by step.
  def first_setup(**steps)
    {
      account: { first_name: "Alex", last_name: "", username: "ops", email: "ops@example.com", password: "a-long-password",
                 password_confirmation: "a-long-password", locale: "en" },
      household: { name: "Casa Nuova", currency: "EUR" },
      allowances: { assistant: "1", uploads: "1", pictures: "1", invitations: "1", push_notifications: "1", release_check: "1",
                    assistant_messages_per_day: "", files_quota_amount: "50", files_quota_unit: "GB", household_size: "", invitations_per_member: "" },
      assistant: { provider: "ollama", model: "qwen3:8b", ollama_url: "http://localhost:11434" },
      books: { google_books_api_key: "", book_lookups_per_day: "" },
      mail: { outgoing_mail: "1", smtp_host: "", smtp_port: "", smtp_tls: "", smtp_username: "", smtp_password: "", mail_from: "",
              mails_per_hour: "6", mails_per_day: "40", reminder_mails_per_day: "20" }
    }.deep_merge(steps)
  end

  # Kamal's proxy asks it before a new version takes traffic
  # (config/deploy.yml), a destination's first boot included.
  test "the health check answers with nobody in the database, never sent to the setup page" do
    with_empty_database { get rails_health_check_path }

    assert_response :success
  end

  test "with anyone in the database the page is gone and nothing is created" do
    get setup_path
    assert_redirected_to new_profile_session_path

    assert_no_difference [ -> { Household.count }, -> { Profile.count } ] do
      post setup_path, params: { setup: first_setup }
    end
    assert_redirected_to new_profile_session_path

    get new_profile_session_path
    assert_response :success
  end

  test "on an empty database every visitor is sent to the setup page" do
    with_empty_database do
      get root_path
      assert_redirected_to setup_path
      get new_profile_session_path
      assert_redirected_to setup_path

      give_the_setup_code
      get setup_path
      assert_response :success
      assert_select "form[action=?][data-controller=setup-wizard]", setup_path do
        assert_select "input[name='setup[account][username]'][required]"
        assert_select "input[name='setup[account][password_confirmation]'][type=password]"
        assert_select "input[name='setup[household][currency]'][value=EUR]"
        assert_select "input[type=checkbox][name='setup[allowances][uploads]'][checked]"
        assert_select "[data-setup-wizard-when='setup[allowances][assistant]']" do
          assert_select "input[name='setup[assistant][provider]']", 3
          assert_select "turbo-frame#assistant-settings-models[loading=lazy][src=?]", setup_assistant_models_path(provider: "ollama")
          assert_select "button[type=submit][formaction=?][formnovalidate]", setup_assistant_test_path
          assert_select "turbo-frame#assistant-settings-connection"
        end
        assert_select "input[name='setup[books][google_books_api_key]'][type=password]"
        assert_select "template input[name='setup[housemates][people][NEW_RECORD][email]']"
        assert_select "button[type=submit][data-turbo=false]", count: 1, text: /Create/
      end
    end
  end

  test "the first account is made, signed in, and runs the app" do
    with_empty_database do
      give_the_setup_code
      assert_difference [ -> { Household.count }, -> { Profile.admin.count } ], 1 do
        post setup_path, params: { setup: first_setup }
      end
    end
    assert_redirected_to root_path
    assert_match(/Casa Nuova/, flash[:success])

    household = Household.find_by!(name: "Casa Nuova")
    admin = household.owner
    assert_predicate admin, :admin?
    assert_equal "ops", admin.username
    assert admin.valid_password?("a-long-password")

    get admin_households_path
    assert_response :success
    assert_select ".account-menu__name", text: "Alex"
  end

  test "the household's name is text in the welcome toast on the next page, never markup" do
    with_empty_database do
      give_the_setup_code
      post setup_path, params: { setup: first_setup(household: { name: "<img src=x onerror=alert(1)>" }) }
    end
    follow_redirect!

    assert_response :success
    assert_no_injected_markup
    assert_toast "<img src=x onerror=alert(1)>"
  end

  test "a mistake brings the form back with what was typed and what was wrong; nothing is created" do
    with_empty_database do
      give_the_setup_code
      assert_no_difference [ -> { Household.count }, -> { Profile.count } ] do
        post setup_path, params: { setup: first_setup(household: { name: "" }, account: { email: "not-an-email", password: "short", password_confirmation: "other" }) }
      end
      assert_response :unprocessable_content
      assert_select "input[name='setup[account][username]'][value=ops]"
      assert_select "input[name='setup[account][password]'][value]", count: 0
      assert_select "form[data-setup-wizard-start-value='0']", true, "the page opens at the first step with something to fix"
      assert_form_error "Household name can't be blank"
      assert_form_error(/\APassword confirmation/)
      assert_select "#setup_household_name_error", text: "Household name can't be blank"
      assert_select ".field.is-invalid input#setup_account_email[aria-describedby=setup_account_email_error]"
      assert_select "input#setup_account_password[aria-invalid=true][aria-describedby='setup_account_password_rule setup_account_password_error']"
    end
  end

  test "the first account spends the setup code, so an emptied database later needs a new one" do
    with_empty_database do
      give_the_setup_code
      post setup_path, params: { setup: first_setup }
    end

    assert_nil Platform.setup_code_digest
  end

  test "everything the setup asks is saved at once, and the invitation links are shown once" do
    with_empty_database do
      give_the_setup_code
      post setup_path, params: { setup: first_setup(
        account: { locale: "it" },
        household: { currency: "chf" },
        allowances: { uploads: "0", files_quota_amount: "20", files_quota_unit: "GB", assistant_messages_per_day: "40", household_size: "6", invitations_per_member: "4" },
        assistant: { provider: "anthropic", model: "claude-test", anthropic_api_key: "sk-ant-secret" },
        books: { google_books_api_key: "books-key", book_lookups_per_day: "7" },
        housemates: { people: { "0" => { first_name: "", email: "" }, "1" => { first_name: "Robin", email: "Robin@Example.com" } } }
      ) }
    end

    assert_response :success
    owner = Household.find_by!(name: "Casa Nuova").owner
    assert_equal [ "Alex", "it", "CHF" ], [ owner.first_name, owner.locale, owner.household.currency ]
    assert_equal [ "robin@example.com" ], owner.household.invitations.pluck(:email)
    assert_not Platform.uploads?
    assert_equal [ 20.gigabytes, 40, 6, 4, 7, "books-key" ], [ Platform.files_quota, Platform.assistant_messages_per_day, Platform.household_size,
                                                               Platform.invitations_per_member, Platform.book_lookups_per_day, Platform.google_books_api_key ]
    assert_equal [ "anthropic", "claude-test", "sk-ant-secret" ], [ Assistant.provider.to_s, Assistant.model, Assistant.api_key(:anthropic) ]

    assert_select "h1", I18n.t("setup.done.title", locale: :it)
    assert_select ".household__link-url[value*='invitation_token=']", 1
    get root_path
    assert_response :success, "the admin is signed in"
  end

  test "with the assistant off its step is neither checked nor saved" do
    with_empty_database do
      give_the_setup_code
      post setup_path, params: { setup: first_setup(allowances: { assistant: "0" }, assistant: { provider: "openai", model: "" }) }
    end

    assert_redirected_to root_path
    assert_not Platform.assistant?
    assert_nil Assistant::Setting.saved
  end

  test "a housemate who can't be invited keeps everything from being made, and the page opens at their step" do
    with_empty_database do
      give_the_setup_code
      assert_no_difference [ -> { Household.count }, -> { Profile.count }, -> { Platform::Setting.where.not(updated_by: nil).count } ] do
        post setup_path, params: { setup: first_setup(housemates: { people: { "0" => { first_name: "Me", email: "OPS@example.com" },
                                                                              "1" => { first_name: "Sam", email: "sam.example.com" } } }) }
      end
    end

    assert_response :unprocessable_content
    assert_form_error "Who else lives here, row 1: Email is yours: you're in already"
    assert_form_error "Who else lives here, row 2: Email is invalid"
    assert_select "form[data-setup-wizard-start-value='#{Setup::STEPS.index(Setup::Housemates)}']"
    assert_select ".setup-housemates__row.is-invalid input[name='setup[housemates][people][1][email]'][value='sam.example.com'][aria-invalid=true]"
  end

  test "a limit the environment sets is where the setup starts, and the admin's answer is what is kept" do
    with_env("UPLOADS" => "off", "FILES_QUOTA" => "512MB") do
      with_empty_database do
        give_the_setup_code
        get setup_path
        assert_select "input[type=checkbox][name='setup[allowances][uploads]']:not([checked]):not([disabled])"
        assert_select "input[name='setup[allowances][files_quota_amount]'][value='512']"

        post setup_path, params: { setup: first_setup(allowances: { uploads: "1" }) }
      end

      assert_predicate Platform, :uploads?
      assert Platform::Setting.sole.uploads
    end
  end
end
