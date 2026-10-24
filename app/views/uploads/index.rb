# frozen_string_literal: true

# The Files section: the results frame with the household's storage gauge,
# the scope pills and the rows. The search and the upload button are the
# top bar's. Live for the viewer's own files and the ones shared with them
# (Uploads::Broadcaster).
class Views::Uploads::Index < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  # quota: the household's room for files (Uploads::Quota), for the gauge.
  def initialize(uploads:, viewer:, scope:, counts:, query:, quota:)
    @uploads = uploads
    @viewer = viewer
    @scope = scope
    @counts = counts
    @query = query
    @quota = quota
  end

  def page_title = t("uploads.index.title")

  # No upload button where uploads are switched off (UploadPolicy#create?).
  def navbar_controls
    search = Components::IndexSearch.new(url: routes.uploads_path, results: Views::Uploads::List, query: @query,
                                         placeholder: t("uploads.index.search_placeholder"), hidden: { scope: @scope }.compact)
    actions = []
    if Pundit.policy!(@viewer, Upload).create?
      actions << Components::Action.new(href: routes.new_upload_path, icon: "fa-plus", label: t("uploads.index.new"), turbo_stream: true)
    end
    Components::PageControls.new(search: search, actions: actions)
  end

  def view_template
    div(class: "uploads") do
      turbo_stream_from @viewer, :uploads
      render Components::PageHeader.new(title: t("uploads.index.title"))
      render Views::Uploads::List.new(uploads: @uploads, viewer: @viewer, scope: @scope, counts: @counts, query: @query, quota: @quota)
    end
  end
end
