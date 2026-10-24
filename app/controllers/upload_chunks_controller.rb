# frozen_string_literal: true

# The next chunk of a file still coming up, from the upload modal
# (uploader_controller.js): the raw body, at the place the Upload-Offset
# header names. 204 with the new offset when it was appended; 409 with the
# real offset when it wasn't the next one, so the page goes on from there;
# 413 when it doesn't fit; 422 once the upload is past taking chunks, with
# its status, so a page whose last chunk's answer was lost knows it is all
# there.
class UploadChunksController < ApplicationController
  def create
    upload = policy_scope(Upload).find(params[:upload_id])
    authorize upload, :chunk?

    offset = Integer(request.headers["Upload-Offset"], exception: false)
    return render(json: { error: t("uploads.errors.no_offset") }, status: :bad_request) if offset.nil? || offset.negative?

    result = Uploads::Append.call(upload, io: request.body, offset: offset, length: request.content_length)
    response.set_header("Upload-Offset", result.offset.to_s)
    case result.error
    when nil then head :no_content
    when :conflict then render json: { offset: result.offset }, status: :conflict
    when :too_large then render json: { offset: result.offset, error: t("uploads.errors.chunk_too_large") }, status: :content_too_large
    else render json: { offset: result.offset, status: upload.status }, status: :unprocessable_content
    end
  end
end
