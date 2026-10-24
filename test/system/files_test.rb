# frozen_string_literal: true

require "application_system_test_case"

# A file kept on the server: it goes up in chunks (uploader_controller.js),
# is checked once whole (Uploads::FinishJob), and a link shown once lets
# someone with no account download it. (Resuming from the offset the server
# names is the request tests': UploadsControllerTest.)
class FilesTest < ApplicationSystemTestCase
  test "a file goes up, gets a link shown once, and someone without an account downloads it" do
    file = Rails.root.join("tmp/test-files", "lease-#{SecureRandom.hex(4)}.txt").tap { _1.dirname.mkpath }
    file.write("The lease, signed.\n")
    sign_in profiles(:alice)
    visit uploads_path

    perform_enqueued_jobs(only: Uploads::FinishJob) do
      click_on I18n.t("uploads.index.new")
      within(".modal") { find(".uploader__input", visible: :all).set(file.to_s) }
      assert_selector ".upload-row", text: file.basename.to_s
      assert_selector ".upload-row button[aria-label='#{I18n.t("uploads.row.download")}']" # ready: checked and kept
    end
    find(".modal__close").click

    within(".upload-row", text: file.basename.to_s) do
      click_on I18n.t("uploads.row.more")
      click_on I18n.t("uploads.row.link")
    end
    within(".modal") { click_on I18n.t("upload_links.form.create") }
    link = find(".upload-links__fresh input").value
    upload = Upload.find_by!(name: file.basename.to_s)

    using_session(:stranger) do
      visit link
      assert_text file.basename.to_s
      click_on I18n.t("upload_links.public.show.download")
    end
    assert_eventually { upload.upload_links.sole.reload.downloads_count == 1 }
  ensure
    file&.delete if file&.exist?
  end
end
