# frozen_string_literal: true

require "test_helper"

# What production shows when a request fails: the page from public/
# (ErrorPages), never the development's report of the error.
class ErrorPagesTest < ActionDispatch::IntegrationTest
  OLD_BROWSER = "Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko"

  test "a wrong address is answered in the language the person was reading, though no controller ran" do
    alice = profiles(:alice).tap { _1.update!(locale: "it") }
    sign_in alice
    get root_path, headers: { "Accept-Language" => "en" }

    as_in_production { get "/no-such-page", headers: { "Accept-Language" => "en" } }

    assert_response :not_found
    assert_select "html[lang=it]"
    assert_select "h1", I18n.t("public_pages.pages.not_found.title", locale: :it)
  end

  test "a crash is answered in the person's language" do
    alice = profiles(:alice).tap { _1.update!(locale: "it") }
    sign_in alice

    as_in_production do
      swapping(Navbar::Facts, :for, ->(*) { raise "the page broke" }) { get root_path, headers: { "Accept-Language" => "en" } }
    end

    assert_response :internal_server_error
    assert_select "h1", I18n.t("public_pages.pages.server_error.title", locale: :it)
  end

  test "a stranger is answered in their browser's language, else the default" do
    as_in_production { get "/no-such-page", headers: { "Accept-Language" => "it-IT,it;q=0.9" } }
    assert_select "html[lang=it]"

    as_in_production { get "/no-such-page", headers: { "Accept-Language" => "fr" } }
    assert_select "html[lang=en]"
  end

  test "a language the session no longer holds valid is passed over for the browser's" do
    pages = ErrorPages.new(Rails.public_path)
    env = Rack::MockRequest.env_for("/404", "HTTP_ACCEPT_LANGUAGE" => "it", "rack.session" => { "locale" => "xx" })

    status, _, body = pages.call(env)

    assert_equal 404, status
    assert_includes body.join, %(<html lang="it">)
  end

  test "an old browser is turned away in its own language" do
    get new_profile_session_path, headers: { "Accept-Language" => "it", "User-Agent" => OLD_BROWSER }

    assert_response :not_acceptable
    assert_select "h1", I18n.t("public_pages.pages.not_acceptable.title", locale: :it)
  end

  private

  # The test environment shows the error itself, as development does; the
  # app merges its settings into every request, so they are changed there.
  def as_in_production(&)
    settings = Rails.application.env_config.merge(
      "action_dispatch.show_detailed_exceptions" => false, "action_dispatch.show_exceptions" => :all
    )
    swapping(Rails.application, :env_config, -> { settings }, &)
  end
end
