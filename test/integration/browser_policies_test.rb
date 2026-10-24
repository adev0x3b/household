# frozen_string_literal: true

require "test_helper"

class BrowserPoliciesTest < ActionDispatch::IntegrationTest
  test "every page carries the policy: the app's own sources only, never framed" do
    sign_in profiles(:carol)

    get root_path

    assert_response :success
    assert_equal "'self'", directive("default-src")
    assert_match(/\A'self' 'wasm-unsafe-eval' 'nonce-[^']+'\z/, directive("script-src"))
    assert_match(/\A'self' 'nonce-[^']+'\z/, directive("style-src"))
    assert_equal "'unsafe-inline'", directive("style-src-attr")
    assert_equal "'self'", directive("font-src")
    assert_equal "'self'", directive("connect-src")
    assert_equal "'none'", directive("frame-ancestors")
    assert_equal "'none'", directive("object-src")
  end

  test "a first visit, with no session yet, gets a nonce its inline scripts carry" do
    get new_profile_session_path

    assert_response :success
    assert_operator nonce.length, :>=, 16
    inline = Nokogiri::HTML5(response.body).css("script:not([src])")
    assert_predicate inline, :any?
    inline.each { assert_equal nonce, _1["nonce"], _1.to_html.truncate(80) }
    assert_select "meta[name='csp-nonce'][content=?]", nonce
  end

  test "the nonce lasts as long as the session, sign-in included: Turbo's visits keep the first page's policy" do
    get new_profile_session_path
    first = nonce

    get new_profile_session_path
    assert_equal first, nonce

    profile = profiles(:carol).tap { _1.update!(password: "a-long-password") }
    post profile_session_path, params: { profile: { login: profile.username, password: "a-long-password" } }
    follow_redirect!
    assert_equal first, nonce
  end

  test "the browser features the app uses are its own pages', every other one is off" do
    get new_profile_session_path

    policy = response.headers["Permissions-Policy"].split(",").map(&:strip).to_h { _1.split("=", 2) }
    assert_equal({ "autoplay" => "(self)", "camera" => "(self)", "screen-wake-lock" => "(self)" }, policy.select { _2 != "()" })
    assert_equal "()", policy["geolocation"]
    assert_equal "()", policy["microphone"]
  end

  test "icons come from the app's own assets, not a CDN" do
    get new_profile_session_path

    assert_select "link[rel=stylesheet][href*='fontawesome']"
    assert_select "link[href^='http']", false
  end

  test "every cookie the app sets goes to its own path only: under a mount path the domain is shared" do
    profile = profiles(:carol).tap { _1.update!(password: "a-long-password") }
    post profile_session_path, params: { profile: { login: profile.username, password: "a-long-password", remember_me: "1" } }
    set = cookie_paths
    with_push_keys { post push_subscription_path, params: { subscription: browser_subscription }, as: :json }
    set.merge!(cookie_paths)

    assert_equal %w[_household_session push_subscription remember_profile_token], set.keys.sort
    set.each { |name, path| assert_equal Rails.configuration.x.cookie_path, path, name }
  end

  private

  # Each cookie the last answer set, with the path it named.
  def cookie_paths
    Array(response.headers["Set-Cookie"]).flat_map { _1.split("\n") }.to_h do |cookie|
      [ cookie[/\A[^=]+/], cookie[/;\s*path=([^;]*)/i, 1] ]
    end
  end

  def directive(name)
    response.headers["Content-Security-Policy"].split(";").map(&:strip)
      .find { _1.start_with?("#{name} ") }&.delete_prefix("#{name} ")
  end

  def nonce = directive("script-src")[/'nonce-([^']+)'/, 1].to_s
end
