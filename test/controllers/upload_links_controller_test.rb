# frozen_string_literal: true

require "test_helper"

class UploadLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @lease = uploads(:lease)
    sign_in @alice
  end

  test "the modal, then a link shown once with its address, on the trail; revoked from the panel" do
    get new_upload_upload_link_path(@lease), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target=modals] select[name='upload_link[lifetime_days]'] option[value='7'][selected]"
    assert_select "select[name='upload_link[max_downloads]'] option[value='unlimited']"

    assert_difference [ -> { @lease.upload_links.count }, -> { @lease.upload_activities.count } ], 1 do
      post upload_upload_links_path(@lease), params: { upload_link: { lifetime_days: "30", max_downloads: "5", password: "open sesame" } }, as: :turbo_stream
    end
    assert_response :success
    link = @lease.upload_links.last
    # The address comes back in a modal of its own, whether the form was
    # opened from the list or the page: the list has no panel to show it in.
    assert_select "turbo-stream[action=update][target=modals] .upload-links__fresh input[value^=?]", "http://www.example.com#{Rails.configuration.x.mount_path}/s/"
    token = css_select(".upload-links__fresh input").first["value"].split("/s/").last
    assert_equal link, UploadLink.find_by_token(token)
    assert_select "turbo-stream[action=update][target=modals] .upload-link-form__note", text: /5 downloads.*Password protected/
    assert_select ".modal__footer .modal__btn--cancel", text: I18n.t("modal.done"), message: "the link is made: nothing to cancel"
    assert_select "turbo-stream[action=replace][target=upload-#{@lease.id}-links] .upload-links__fresh", count: 0
    assert_equal [ 5, true ], [ link.max_downloads, link.protected? ]
    assert_in_delta 30.days.from_now, link.expires_at, 5
    assert_select ".upload-links__item--active .status-badge", text: /Active/
    assert_select ".upload-links__item-meta", text: /0 of 5 downloads/
    assert_select ".upload-links__lock"
    assert_equal "link_created", @lease.upload_activities.last.action

    get upload_path(@lease)
    assert_select ".upload-links__fresh", count: 0 # never shown again
    assert_select ".upload-links__item a.item-action[data-turbo-method=delete][href=?]", upload_link_path(link)

    delete upload_link_path(link), as: :turbo_stream
    assert_response :success
    assert_predicate link.reload, :revoked?
    assert_select ".upload-links__item--revoked .status-badge", text: /Revoked/
    assert_equal "link_revoked", @lease.upload_activities.last.action
  end

  test "the defaults: a week, one download, no password; a bad lifetime falls back" do
    post upload_upload_links_path(@lease), params: { upload_link: { lifetime_days: "99", max_downloads: "", password: "" } }, as: :turbo_stream
    link = @lease.upload_links.last
    assert_equal [ 1, false ], [ link.max_downloads, link.protected? ]
    assert_in_delta 7.days.from_now, link.expires_at, 5
  end

  test "only the owner, only a whole file, never with uploads off" do
    get new_upload_upload_link_path(uploads(:backup)), as: :turbo_stream
    assert_response :forbidden

    sign_in profiles(:bob)
    get uploads_path # a 404 first would drop the test sign-in before its session is saved
    assert_no_difference -> { UploadLink.count } do
      post upload_upload_links_path(@lease), params: { upload_link: { lifetime_days: "7" } }, as: :turbo_stream
    end
    assert_response :not_found
    delete upload_link_path(mint_link(@lease).first), as: :turbo_stream
    assert_response :not_found
    assert_equal [ false ], @lease.upload_links.map(&:revoked?)

    with_env("UPLOADS" => "off") do
      sign_in profiles(:alice)
      assert_no_difference -> { UploadLink.count } do
        post upload_upload_links_path(@lease), params: { upload_link: { lifetime_days: "7" } }, as: :turbo_stream
      end
      assert_response :forbidden
      get upload_path(@lease)
      assert_select "#upload-#{@lease.id}-links", count: 0
      assert_select ".item-menu__entry[href=?]", new_upload_upload_link_path(@lease), count: 0
    end
  end
end
