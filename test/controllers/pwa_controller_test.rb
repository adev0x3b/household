# frozen_string_literal: true

require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "the manifest makes the app installable, in the visitor's language, signed in or not" do
    get pwa_manifest_path, headers: { "Accept-Language" => "it" }

    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    assert_equal "no-cache", response.headers["Cache-Control"]
    manifest = JSON.parse(response.body)
    assert_equal [ root_path, root_path, root_path, "standalone", "it" ], manifest.values_at("id", "start_url", "scope", "display", "lang")
    assert_equal I18n.t("pwa.manifest.description", locale: :it), manifest["description"]
    assert_equal(%w[192x192 512x512], manifest["icons"].select { _1["purpose"] == "any" && _1["type"] == "image/png" }.map { _1["sizes"] })
    assert(manifest["icons"].any? { _1["purpose"] == "maskable" })
    manifest["icons"].each { assert_path_exists Rails.public_path.join(_1["src"].delete_prefix("/")), _1["src"] }
  end

  test "the service worker is served fresh, as JavaScript, to the browser itself" do
    with_push_keys { get pwa_service_worker_path }

    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_equal "no-cache", response.headers["Cache-Control"]
    assert_equal root_path, response.headers["Service-Worker-Allowed"]
    I18n.available_locales.each { assert_includes response.body, %("#{pwa_offline_path(locale: _1)}") }
    assert_includes response.body, PushBuilders::VAPID.public_key
    assert_includes response.body, push_subscription_path
  end

  test "the offline page needs no session and no navbar" do
    get pwa_offline_path(locale: :en)

    assert_response :success
    assert_select "h1", I18n.t("pwa.offline.title", locale: :en)
    assert_select ".navbar-topbar", 0
  end

  test "the offline page is in the language its address names, whatever the browser or the person reads" do
    alice = profiles(:alice).tap { _1.update!(locale: "en") }
    sign_in alice

    get pwa_offline_path(locale: :it), headers: { "Accept-Language" => "en" }

    assert_select "html[lang=it]"
    assert_select "h1", I18n.t("pwa.offline.title", locale: :it)
  end

  test "trying again asks for the page that failed, which is the address the offline page was shown at" do
    get pwa_offline_path(locale: :en)

    assert_select "a[href='']", I18n.t("pwa.offline.retry", locale: :en)
  end

  test "a language the app doesn't speak has no offline page" do
    get "/offline/fr"

    assert_response :not_found
  end

  test "every page links the manifest and names the service worker" do
    sign_in profiles(:alice)
    get root_path

    assert_select "link[rel=manifest][href=?]", pwa_manifest_path
    assert_select "meta[name=service-worker][content=?][data-scope=?]", pwa_service_worker_path, root_path
    assert_select "meta[name=theme-color]"
    assert_select "meta[name=viewport][content*=?]", "viewport-fit=cover"
  end
end
