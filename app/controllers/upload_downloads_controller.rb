# frozen_string_literal: true

# Pressing Download, by whoever may see the file: the download goes on the
# file's trail, and the browser is sent to the bytes. The press is a POST
# so that only a person's tap records a download, never a prefetch or a
# transfer the browser resumed.
class UploadDownloadsController < ApplicationController
  def create
    upload = policy_scope(Upload).includes(:profile, :upload_shares, :shared_profiles).find(params[:upload_id])
    authorize upload, :download?

    UploadActivity.record(upload, :downloaded, actor: current_profile, request: request)
    redirect_to file_upload_path(upload), status: :see_other
  end
end
