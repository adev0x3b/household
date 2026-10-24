# frozen_string_literal: true

require "test_helper"

class UploadDownloadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @lease = write_upload_file(uploads(:lease), "lease terms")
    @photo = write_upload_file(uploads(:photo), "jpeg!") # bob's, shared with alice
    @backup = uploads(:backup)
    sign_in @alice
  end

  test "pressing Download puts one download on the trail and leads to the file" do
    assert_difference -> { @photo.upload_activities.where(action: "downloaded", profile: @alice).count }, 1 do
      post upload_downloads_path(@photo)
    end
    assert_redirected_to file_upload_path(@photo)
    assert_response :see_other

    post upload_downloads_path(@backup)
    assert_response :redirect
    assert_not_equal file_upload_path(@backup), response.location, "a file still coming has nothing to download"

    sign_in profiles(:carol)
    post upload_downloads_path(@lease)
    assert_response :not_found
  end
end
