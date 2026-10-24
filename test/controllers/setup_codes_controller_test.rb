# frozen_string_literal: true

require "test_helper"

# The setup page asks for the copy's one-time code before anything else, so
# whoever reaches a fresh copy's address before its owner can't make the
# first account.
class SetupCodesControllerTest < ActionDispatch::IntegrationTest
  include RateLimits

  def with_empty_database
    Household.find_each { |household| Households::Destroy.call(household) }
    yield
  end

  def first_account
    { account: { username: "ops", email: "ops@example.com", password: "a-long-password", password_confirmation: "a-long-password" },
      household: { name: "Casa Nuova", currency: "EUR" } }
  end

  test "without a code the page offers no setup, only the command that makes one" do
    with_empty_database do
      get setup_path

      assert_response :success
      assert_select ".auth-card form", count: 0
      assert_select ".auth-card__command", text: "bin/rails setup:code"
      assert_no_difference -> { Profile.count } do
        post setup_path, params: { setup: first_account }
      end
      assert_redirected_to setup_path
    end
  end

  test "with a code the page asks for it and shows nothing of the setup" do
    with_empty_database do
      SetupCodes::Renew.call
      get setup_path

      assert_response :success
      assert_select "form[action=?]", setup_code_path
      assert_select "input[name='setup_code[code]'][required][autocomplete=one-time-code]"
      assert_select "input[name='setup[account][username]']", count: 0
    end
  end

  test "a wrong code is refused with the same words, and opens nothing" do
    with_empty_database do
      SetupCodes::Renew.call
      post setup_code_path, params: { setup_code: { code: "AAAA-BBBB-CCCC-DDDD" } }

      assert_response :unprocessable_content
      assert_select ".field.is-invalid .field__error", text: "That isn't this copy's setup code."
      assert_select "input[name='setup_code[code]'][aria-invalid=true][aria-describedby=setup_code_code_error]"
      assert_no_difference -> { Profile.count } do
        post setup_path, params: { setup: first_account }
      end
      assert_redirected_to setup_path
    end
  end

  test "the right code opens the setup, typed in any case and spacing" do
    with_empty_database do
      code = SetupCodes::Renew.call.code
      post setup_code_path, params: { setup_code: { code: " #{code.downcase.tr("-", " ")} " } }

      assert_redirected_to setup_path
      follow_redirect!
      assert_select "input[name='setup[account][username]']"
    end
  end

  test "a new code shuts out the browser that gave the old one" do
    with_empty_database do
      post setup_code_path, params: { setup_code: { code: SetupCodes::Renew.call.code } }
      SetupCodes::Renew.call
      get setup_path

      assert_select "form[action=?]", setup_code_path
    end
  end

  test "guessing is limited by address" do
    with_empty_database do
      code = SetupCodes::Renew.call.code
      counting_rate_limits do
        5.times { post setup_code_path, params: { setup_code: { code: "AAAA-BBBB-CCCC-DDDD" } } }
        post setup_code_path, params: { setup_code: { code: code } }
      end

      assert_redirected_to setup_path
      assert_equal "Too many attempts. Wait a moment and try again.", flash[:alert]
      follow_redirect!
      assert_select "form[action=?]", setup_code_path
    end
  end

  test "a development server makes its own code and prints it where it runs" do
    with_empty_database do
      assert_nil Platform::Setting.first&.setup_code_digest, "no code yet, so the server makes one"

      swapping(Rails.configuration.x, :makes_its_own_setup_code, -> { true }) do
        assert_output(nil, /Household's setup code: ([A-Z2-9]{4}-){3}[A-Z2-9]{4}/) { get setup_path }
      end
      assert_response :success

      assert_select "form[action=?]", setup_code_path
      assert_predicate Platform.setup_code_digest, :present?
    end
  end

  test "the code is printed with Ruby's warnings off too" do
    with_empty_database do
      swapping(Rails.configuration.x, :makes_its_own_setup_code, -> { true }) do
        verbose, $VERBOSE = $VERBOSE, nil
        assert_output(nil, /Household's setup code: /) { get setup_path }
      ensure
        $VERBOSE = verbose
      end
    end
  end

  test "once anyone exists the code opens nothing" do
    post setup_code_path, params: { setup_code: { code: "AAAA-BBBB-CCCC-DDDD" } }

    assert_redirected_to new_profile_session_path
  end
end
