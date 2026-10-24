# frozen_string_literal: true

# The Files section: one's own files and the ones housemates shared, a page
# per file, and the upload itself — in chunks, resumable, from the upload
# modal (uploader_controller.js):
#   create     the row, with the name and size declared (JSON)
#   chunks     the next chunk, raw, at the offset the Upload-Offset header says (UploadChunksController)
#   progress   where the upload has got to (JSON), to go on after a reload
# Then the file: its bytes, for the owner and whoever it is shared with
# (pressing Download is UploadDownloadsController's), rename, delete.
# Sharing it is SharesController's, its public links UploadLinksController's.
class UploadsController < ApplicationController
  include SearchableIndex

  before_action :set_upload, only: %i[show edit update destroy file progress]
  rate_limit_per_person to: 20, within: 1.hour, only: :create

  def index
    authorize Upload

    query = Uploads::IndexQuery.new(viewer: current_profile, search: search_query, scope: params[:scope], page: params[:page])
    shown = { uploads: query.uploads, viewer: current_profile, scope: query.scope, counts: query.counts, query: search_query,
              quota: Uploads::Quota.new(current_profile.household) }

    render_searchable_index(page: Views::Uploads::Index.new(**shown), results: Views::Uploads::List.new(**shown))
  end

  def show
    authorize @upload
    ActiveRecord::Associations::Preloader.new(records: [ @upload ], associations: { upload_shares: :profile }).call # who has it, by name

    render_page Views::Uploads::Show.new(upload: @upload, viewer: current_profile, page: Uploads::Page.new(@upload))
  end

  # The upload modal: pick files, watch them go up.
  def new
    authorize Upload

    render_modal(Views::Uploads::Modals::Upload.new(space_left: Uploads::Quota.new(current_profile.household).left), page: uploads_path)
  end

  # JSON: { name, byte_size, content_type } → the upload to send chunks to.
  def create
    authorize Upload

    result = Uploads::Create.call(owner: current_profile, name: params[:name], byte_size: params[:byte_size], content_type: params[:content_type])
    if result.success?
      render json: upload_json(result.upload), status: :created
    else
      render json: { error: error_message(result) }, status: :unprocessable_content
    end
  end

  def progress
    authorize @upload

    render json: upload_json(@upload)
  end

  def edit
    authorize @upload

    render_modal(form_view(@upload), page: @upload)
  end

  def update
    authorize @upload

    if @upload.update(upload_params)
      Uploads::Broadcaster.changed(@upload)
      redirect_back_after_save(upload_path(@upload), notice: t("uploads.notices.renamed"))
    else
      render turbo_stream: redraw_modal(form_view(@upload)), status: :unprocessable_content
    end
  end

  # The file itself, as an attachment. Thruster serves it from the
  # X-Sendfile header in production (ranges included, so a download cut
  # short can go on), Puma streams it in development.
  def file
    authorize @upload, :download?

    response.set_header("Cache-Control", "private, no-store")
    send_file @upload.path, filename: @upload.name, type: @upload.content_type || "application/octet-stream", disposition: "attachment"
  end

  def destroy
    authorize @upload

    viewers = @upload.people_with_access - [ current_profile ]
    Uploads::Destroy.call(@upload)
    Uploads::Broadcaster.removed(@upload, viewers)

    redirect_after_destroy(upload_path(@upload), list: uploads_path, notice: t("uploads.notices.destroyed"))
  end

  private

  def set_upload
    @upload = policy_scope(Upload).includes(:profile, :upload_shares, :shared_profiles).find(params[:id])
  end

  def upload_params = params.expect(upload: [ :name ])

  def upload_json(upload)
    { id: upload.id, offset: upload.received_bytes, byte_size: upload.byte_size, status: upload.status, chunk_size: Upload::CHUNK_SIZE,
      chunk_url: upload_chunks_path(upload), progress_url: progress_upload_path(upload), url: upload_path(upload) }
  end

  def error_message(result)
    case result.error
    when :quota then t("uploads.errors.quota", left: helpers.number_to_human_size(Uploads::Quota.new(current_profile.household).left))
    when :too_large then t("uploads.errors.too_large", max: helpers.number_to_human_size(Upload::MAX_SIZE))
    else result.upload.errors.full_messages.to_sentence
    end
  end

  def form_view(upload) = Views::Uploads::Modals::Form.new(upload: upload, url: upload_path(upload))
end
