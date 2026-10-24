# frozen_string_literal: true

require "test_helper"

class UploadLinks::PublicControllerTest < ActionDispatch::IntegrationTest
  setup do
    @lease = write_upload_file(uploads(:lease), "lease terms")
  end

  test "a link opens the file to anyone: the page, the press, the bytes; a one-time link is spent by the press" do
    link, token = mint_link(@lease)

    get public_upload_link_path(token)
    assert_response :success
    assert_select ".public-upload-link__name", text: "Lease 2026.pdf"
    assert_select ".auth-card__subtitle", text: /11 B · shared by Alice/
    assert_select ".public-upload-link__terms", text: /1 download left/
    assert_select "input[type=password]", count: 0
    assert_select "form[action=?] input[type=submit][value=Download]", public_upload_link_path(token)

    post public_upload_link_path(token)
    assert_response :see_other
    assert_match %r{#{Rails.configuration.x.mount_path}/s/#{token}/file\?t=}, response.location
    assert_equal [ 1, "link_downloaded" ], [ link.reload.downloads_count, @lease.upload_activities.last.action ]
    assert_equal "127.0.0.1", @lease.upload_activities.last.ip

    follow_redirect!
    assert_response :success
    assert_equal "lease terms", response.body
    assert_match(/attachment; filename="Lease 2026.pdf"/, response.headers["Content-Disposition"])
    assert_equal "private, no-store", response.headers["Cache-Control"]

    get response.request.url # the same ticket again: a browser resuming
    assert_response :success

    get public_upload_link_path(token)
    assert_response :gone
    assert_select ".auth-card__subtitle", text: /used as many times as it allowed/
    post public_upload_link_path(token)
    assert_response :gone
    assert_equal 1, link.reload.downloads_count
  end

  test "the ticket is for one link, for an hour, and dies with the link" do
    link, token = mint_link(@lease, max_downloads: nil)
    post public_upload_link_path(token)
    ticket = Rack::Utils.parse_query(URI(response.location).query)["t"]

    other, other_token = mint_link(@lease)
    get public_upload_link_file_path(other_token, t: ticket)
    assert_response :not_found # someone else's ticket on a live link reads as missing
    assert_equal 0, other.reload.downloads_count

    get public_upload_link_file_path(token, t: "forged")
    assert_response :not_found

    travel(2.hours) do
      get public_upload_link_file_path(token, t: ticket)
      assert_response :not_found
    end

    link.revoke!
    get public_upload_link_file_path(token, t: ticket)
    assert_response :gone
  end

  test "the ticket opens the file only in the browser that pressed: its address, passed on, opens nothing" do
    _, token = mint_link(@lease, max_downloads: nil)
    post public_upload_link_path(token)
    ticket_url = response.location

    stranger = open_session
    stranger.get ticket_url
    assert_equal 404, stranger.response.status
    assert_not_equal "lease terms", stranger.response.body

    get ticket_url
    assert_response :success
    assert_equal "lease terms", response.body
  end

  test "a password guards the press, and a wrong one goes on the trail" do
    _, token = mint_link(@lease, password: "open sesame")

    get public_upload_link_path(token)
    assert_select "input[type=password][name=password]"

    post public_upload_link_path(token), params: { password: "nope" }
    assert_response :unprocessable_content
    assert_select ".field.is-invalid .field__error", text: "That's not the password."
    assert_select "input[name=password][aria-invalid=true][aria-describedby=password_error]"
    assert_equal [ "link_refused", "wrong_password" ], [ @lease.upload_activities.last.action, @lease.upload_activities.last.data["reason"] ]

    post public_upload_link_path(token), params: { password: "open sesame" }
    assert_response :see_other
  end

  test "the tenth wrong password closes the link for good" do
    link, token = mint_link(@lease, password: "open sesame", max_downloads: nil)

    (UploadLink::MAX_WRONG_PASSWORDS - 1).times { post public_upload_link_path(token), params: { password: "nope" } }
    assert_response :unprocessable_content
    post public_upload_link_path(token), params: { password: "nope" }

    assert_response :gone
    assert_predicate link.reload, :revoked?
    post public_upload_link_path(token), params: { password: "open sesame" }
    assert_response :gone, "not even the right one now"
  end

  test "expired, revoked or unknown: nothing here, in the same card" do
    link, token = mint_link(@lease, lifetime_days: 1)
    travel 2.days do
      get public_upload_link_path(token)
      assert_response :gone
      assert_select ".auth-card__subtitle", text: /expired/
    end

    link.revoke!
    get public_upload_link_path(token)
    assert_response :gone
    assert_select ".auth-card__subtitle", text: /revoked/

    get public_upload_link_path("no-such-token")
    assert_response :not_found
    assert_select ".auth-card__title", text: "Nothing here"

    half, half_token = mint_link(uploads(:backup))
    assert_not half.persisted?
    assert half.errors.of_kind?(:upload, :not_ready)
    get public_upload_link_path(half_token)
    assert_response :not_found
  end

  test "too many presses from one place are refused" do
    _, token = mint_link(@lease, max_downloads: nil, password: "open sesame")
    counting_rate_limits do
      10.times { post public_upload_link_path(token), params: { password: "nope" } }
      post public_upload_link_path(token), params: { password: "open sesame" }
    end
    assert_response :too_many_requests
    assert_select ".auth-card__subtitle", text: /Too many tries/
  end

  test "too many visits from one place are a page that says so, not a blank one" do
    _, token = mint_link(@lease)
    counting_rate_limits do
      30.times { get public_upload_link_path(token) }
      get public_upload_link_path(token), headers: { "Accept-Language" => "it" }
    end

    assert_response :too_many_requests
    assert_select "html[lang=it]"
    assert_select ".auth-card__subtitle", text: I18n.t("upload_links.public.gone.too_many", locale: :it)
  end

  private

  # Tests cache nothing (the null store), so a rate limit never counts: for
  # the block, the controllers' store counts in memory.
  def counting_rate_limits(&)
    store = ActiveSupport::Cache::MemoryStore.new
    swapping(ApplicationController.cache_store, :increment, ->(*args, **options) { store.increment(*args, **options) }, &)
  end
end
