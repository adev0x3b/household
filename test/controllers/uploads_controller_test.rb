# frozen_string_literal: true

require "test_helper"

class UploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @lease = write_upload_file(uploads(:lease), "lease terms")
    @photo = write_upload_file(uploads(:photo), "jpeg!") # bob's, shared with alice
    @backup = uploads(:backup)
    sign_in @alice
  end

  test "the list shows the quota, the scope pills, a row per file and the navbar's buttons" do
    get uploads_path

    assert_response :success
    assert_select ".uploads__quota .uploads__quota-text", text: /1016 B of 50 GB used/
    assert_select "turbo-frame#uploads_results #uploads_list #upload_#{@lease.id}"
    assert_select "#upload_#{@photo.id} .upload-row__meta", text: /Bob/
    assert_select "#upload_#{@backup.id}.upload-row--pending .status-badge", text: /Uploading, 0%/
    assert_select ".segmented-filter__option[aria-current=true]", text: /All.*3/
    assert_select ".segmented-filter__option[data-turbo-action=replace][href=?]", uploads_path(scope: "shared"), text: /Shared with me.*1/
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_upload_path
    assert_select "a.navbar-link.is-current[href='#{uploads_path}']"
    # One's own, whole: download and share visible, the rest behind "more".
    assert_select "#upload_#{@lease.id} form[action=?][method=post][data-turbo=false] button.item-action", upload_downloads_path(@lease)
    assert_select "#upload_#{@lease.id} a.item-action[href=?]", new_upload_share_path(upload_id: @lease.id)
    assert_select "#upload_#{@lease.id} .item-menu a.item-menu__entry[href=?]", new_upload_upload_link_path(@lease)
    assert_select "#upload_#{@lease.id} .item-menu a.item-menu__entry--danger[href=?][data-turbo-method=delete]", upload_path(@lease)
    # Someone else's: download alone.
    assert_select "#upload_#{@photo.id} form[action=?] button.item-action", upload_downloads_path(@photo)
    assert_select "#upload_#{@photo.id} .item-menu", count: 0
    # Still coming: no download, no share yet.
    assert_select "#upload_#{@backup.id} form[action=?]", upload_downloads_path(@backup), count: 0
    assert_select "#upload_#{@backup.id} a.item-action[href=?]", new_upload_share_path(upload_id: @backup.id), count: 0

    get uploads_path(scope: "shared")
    assert_select "#upload_#{@photo.id}"
    assert_select "#upload_#{@lease.id}", count: 0
    assert_select ".navbar-topbar-controls form input[type=hidden][name=scope][value=shared]"

    sign_in profiles(:carol)
    get uploads_path
    assert_select "#uploads_empty", text: "No files yet. Press Upload files to add one."
  end

  test "the upload modal, then an upload in chunks: created, appended, resumed, finished" do
    get new_upload_path, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target=modals] .uploader[data-controller=uploader][data-uploader-chunk-size-value='#{Upload::CHUNK_SIZE}']"
    assert_select ".uploader[data-uploader-confirm-dialog-outlet='#confirm_dialog']"
    assert_select ".modal__footer .modal__btn--cancel", text: I18n.t("modal.done"), message: "a file is kept as soon as it is up"
    left = ActiveSupport::NumberHelper.number_to_human_size(Uploads::Quota.new(households(:example)).left)
    assert_select ".modal__subtitle", text: /#{Regexp.escape(left)} left in the household's storage/

    assert_difference -> { Upload.count }, 1 do
      post uploads_path, params: { name: "clip.bin", byte_size: 10, content_type: "application/octet-stream" }, as: :json
    end
    assert_response :created
    upload = Upload.last
    body = response.parsed_body
    assert_equal [ upload.id, 0, 10, "uploading", upload_chunks_path(upload) ], body.values_at("id", "offset", "byte_size", "status", "chunk_url")

    post upload_chunks_path(upload), params: "abcd", headers: chunk_headers(0)
    assert_response :no_content
    assert_equal "4", response.headers["Upload-Offset"]

    post upload_chunks_path(upload), params: "abcd", headers: chunk_headers(0) # the same chunk again
    assert_response :conflict
    assert_equal 4, response.parsed_body["offset"]

    get progress_upload_path(upload), as: :json
    assert_equal [ 4, "uploading" ], response.parsed_body.values_at("offset", "status")

    post upload_chunks_path(upload), headers: chunk_headers("nope")
    assert_response :bad_request
    assert_equal I18n.t("uploads.errors.no_offset"), response.parsed_body["error"]

    assert_enqueued_with(job: Uploads::FinishJob) do
      post upload_chunks_path(upload), params: "efghij", headers: chunk_headers(4)
    end
    assert_response :no_content
    assert_predicate upload.reload, :processing?
    assert_equal "abcdefghij", File.read(upload.path)

    post upload_chunks_path(upload), params: "efghij", headers: chunk_headers(4) # its answer lost on the way
    assert_response :unprocessable_content
    assert_equal [ 10, "processing" ], response.parsed_body.values_at("offset", "status")
    assert_equal "10", response.headers["Upload-Offset"]

    perform_enqueued_jobs
    assert_predicate upload.reload, :ready?
    assert_equal Digest::SHA256.hexdigest("abcdefghij"), upload.checksum
  ensure
    Uploads::Storage.delete(upload.key) if upload
  end

  test "an upload that doesn't fit is refused up front" do
    with_env("FILES_QUOTA" => "1100") { post uploads_path, params: { name: "big.bin", byte_size: 500 }, as: :json }

    assert_response :unprocessable_content
    assert_match "Not enough room", response.parsed_body["error"]
  end

  test "nobody feeds or follows someone else's upload" do
    sign_in profiles(:bob)
    get uploads_path # a 404 never writes the session: sign in with a page that answers
    post upload_chunks_path(@backup), params: "x", headers: chunk_headers(0)
    assert_response :not_found
    assert_equal 0, @backup.reload.received_bytes
    assert_not Uploads::Storage.exist?(@backup.key), "no byte of the chunk was kept"
    get progress_upload_path(@backup), as: :json
    assert_response :not_found
    get upload_path(@backup)
    assert_response :not_found
  end

  test "a file's page shows its owner the facts, sharing, links and trail; a sharee sees less" do
    get upload_path(@lease)

    assert_response :success
    assert_select "#upload-#{@lease.id}-page .upload-show__facts dd", text: "PDF"
    assert_select "#upload-#{@lease.id}-page .upload-show__facts", text: /application\/pdf/, count: 0
    assert_select ".upload-show__checksum input[value=?]", @lease.checksum
    assert_select "##{Views::Shares::List.dom_id(@lease, :page)} .empty-state", text: I18n.t("shares.not_shared")
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_upload_share_path(@lease)
    assert_select "#upload-#{@lease.id}-links .empty-state", text: I18n.t("upload_links.panel.empty")
    assert_select "section[aria-label=?] .empty-state", I18n.t("uploads.show.activity"), text: I18n.t("uploads.activity.empty")
    assert_select ".navbar-topbar-controls form[action=?][data-turbo=false] button.page-controls__action", upload_downloads_path(@lease)
    assert_select ".navbar-topbar-controls .item-menu a.item-menu__entry[href=?]", new_upload_upload_link_path(@lease)
    assert_select ".navbar-topbar-controls .item-menu a.item-menu__entry[href=?]", edit_upload_path(@lease)
    assert_select ".navbar-topbar-controls a.item-menu__entry--danger[data-turbo-method=delete][href=?]", upload_path(@lease)
    assert_select "title", text: "Lease 2026.pdf · Household"

    get upload_path(@photo)
    assert_select ".upload-show__shared", text: /Bob/
    assert_select "##{Views::Shares::List.dom_id(@photo, :page)}", count: 0
    assert_select ".navbar-topbar-controls form[action=?] button.page-controls__action", upload_downloads_path(@photo)
    assert_select ".navbar-topbar-controls a[href=?]", new_upload_share_path(upload_id: @photo.id), count: 0
  end

  test "the file comes as an attachment, as often as the browser asks for it, and stays off the trail" do
    assert_no_difference -> { UploadActivity.count } do
      2.times { get file_upload_path(@photo) }
    end

    assert_response :success
    assert_equal "jpeg!", response.body
    assert_match(/attachment; filename="Balcony.jpg"/, response.headers["Content-Disposition"])
    assert_equal "image/jpeg", response.media_type
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    get file_upload_path(@backup)
    assert_response :redirect

    sign_in profiles(:carol)
    get file_upload_path(@lease)
    assert_response :not_found
  end

  test "renaming keeps the file, cleans the name, and comes back to the page it was made on" do
    get edit_upload_path(@lease), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] input[name='upload[name]'][value=?]", "Lease 2026.pdf"

    patch upload_path(@lease), params: { upload: { name: "../Lease signed.pdf" } }, headers: submitted_from(upload_path(@lease))
    assert_redirected_to upload_path(@lease)
    assert_equal "Lease signed.pdf", @lease.reload.name
    follow_redirect!
    assert_select "title", text: /Lease signed.pdf/
    assert_toast "renamed"

    sign_in profiles(:bob)
    patch upload_path(@photo), params: { upload: { name: "" } }, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals]"
    assert_equal "Balcony.jpg", @photo.reload.name
  end

  test "deleting takes the file, its bytes and its shares, and leaves its page; only the owner" do
    sign_in profiles(:bob)
    delete upload_path(@lease), as: :turbo_stream
    assert_response :not_found # not theirs: not even seen
    assert Upload.exists?(@lease.id)

    sign_in @alice
    path = @lease.path
    @lease.upload_shares.create!(profile: profiles(:bob))
    assert_difference [ -> { Upload.count }, -> { UploadShare.count } ], -1 do
      delete upload_path(@lease), headers: submitted_from(upload_path(@lease))
    end
    assert_redirected_to uploads_path
    assert_not File.exist?(path)

    list = uploads_path(scope: "mine", q: "jpg")
    delete upload_path(@backup), headers: submitted_from(list)
    assert_redirected_to list

    delete upload_path(@photo.upload_shares.first.upload) # alice may not delete bob's
    assert_response :redirect
    assert Upload.exists?(@photo.id)
  end

  test "the name on the bell: a share, worded for a file" do
    @lease.upload_shares.create!(profile: profiles(:bob))
    notification = Notifications::Deliver.call(recipient: profiles(:bob), kind: :shared, subject: @lease, actor: @alice)
    assert_equal [ "Alice shared a file with you", "Lease 2026.pdf", upload_path(@lease) ],
                 [ wording_of(notification).title, wording_of(notification).detail, Notifications::Destination.new(notification).path ]
  end

  private

  def chunk_headers(offset)
    { "Content-Type" => "application/offset+octet-stream", "Upload-Offset" => offset.to_s, "Accept" => "application/json" }
  end
end
