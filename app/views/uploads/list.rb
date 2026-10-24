# frozen_string_literal: true

# The results frame of the Files section, rendered with the page, on its
# own as the answer to the navbar search, and reloaded by the upload modal
# as files come in (the storage gauge is in it, so it counts them). The
# scope pills (everything, mine, shared with me) revisit the page with
# `data-turbo-action="replace"`: a page refresh, morphed with the scroll
# kept.
class Views::Uploads::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "uploads_results"
  SCOPE_ICONS = { "all" => "fa-folder-open", "mine" => "fa-user", "shared" => "fa-user-group" }.freeze

  # quota: the household's room for files (Uploads::Quota), for the gauge.
  def initialize(uploads:, viewer:, scope:, counts:, query:, quota:)
    @uploads = uploads
    @viewer = viewer
    @scope = scope
    @counts = counts
    @query = query
    @quota = quota
  end

  def view_template
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      render Views::Uploads::Quota.new(quota: @quota)
      scope_pills
      rows
      render Components::Pagination.new(collection: @uploads, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end

  private

  def scope_pills
    items = ::Uploads::IndexQuery::SCOPES.map do |scope|
      Components::NavItem.new(key: scope, href: uploads_path({ scope: (scope unless scope == "all"), q: @query }.compact),
                              label: t("uploads.index.scope.#{scope}"), count: @counts.fetch(scope, 0), icon: SCOPE_ICONS.fetch(scope))
    end
    render Components::SegmentedFilter.new(items: items, current: @scope, label: t("uploads.index.scope_label"))
  end

  def rows
    div(class: "uploads__list", id: "uploads_list") do
      if @uploads.any?
        @uploads.each { |upload| render Views::Uploads::Row.new(upload: upload, viewer: @viewer) }
      else
        render Components::EmptyState.new(id: "uploads_empty", icon: "fa-folder-open", message: empty_message)
      end
    end
  end

  def empty_message
    if @query.present? then t("uploads.index.empty_search")
    elsif @scope == "shared" then t("uploads.index.empty_shared")
    else t("uploads.index.empty")
    end
  end
end
