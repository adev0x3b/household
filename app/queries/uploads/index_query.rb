# frozen_string_literal: true

module Uploads
  # The Files list as a viewer sees it: their own files and those shared
  # with them, searched, narrowed to a scope (all, mine, shared), newest
  # first, a page at a time — and how many each scope holds, for its pills.
  #
  #   query = Uploads::IndexQuery.new(viewer: profile, search: "invoice", scope: "mine", page: 2)
  #   query.uploads   # the page, with what a row shows preloaded
  #   query.counts    # => { "all" => 12, "mine" => 9, "shared" => 3 }
  class IndexQuery
    SCOPES = %w[all mine shared].freeze
    PER_PAGE = 50

    attr_reader :scope

    def initialize(viewer:, search:, scope:, page:)
      @viewer = viewer
      @search = search
      @scope = scope.presence_in(SCOPES) || "all"
      @page = page
    end

    def uploads
      @uploads ||= scoped.includes(:profile, :upload_shares, :shared_profiles).recent_first.paginate(page: @page, per_page: PER_PAGE)
    end

    # One query: the viewer's own and the rest.
    def counts
      @counts ||= begin
        by_owner = base.group(own).count
        { "all" => by_owner.values.sum, "mine" => by_owner.fetch(true, 0), "shared" => by_owner.fetch(false, 0) }
      end
    end

    private

    def base = Upload.accessible_by(@viewer).search(@search)

    def scoped
      case @scope
      when "mine" then base.where(own)
      when "shared" then base.where.not(own)
      else base
      end
    end

    # Whether a file is the viewer's: what splits the list into its scopes.
    def own = Upload.arel_table[:profile_id].eq(@viewer.id)
  end
end
