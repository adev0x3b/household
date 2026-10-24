# frozen_string_literal: true

module Books
  # The shelf page's one source of truth for what is shown: the viewer's
  # filters (validated from params), the books they pick, and what the
  # filters themselves need — a count per status, the genres present, whose
  # shelves the viewer can switch to. Built from the index's params, and
  # again from the `filters` a card action or a modal form carried, so the
  # results frame comes back as the viewer had it. The page is not a filter:
  # a link that changes the filters starts again from the first.
  class IndexQuery
    DEFAULTS = { sort: "recent", shelf: "mine" }.freeze
    # A whole number of rows at two, three or four covers across.
    PER_PAGE = 24

    Filters = Data.define(:q, :status, :genre, :sort, :shelf) do
      # What a link needs to keep the view: nothing for the defaults.
      def to_params = to_h.compact_blank.reject { |key, value| DEFAULTS[key] == value }
    end

    attr_reader :viewer, :filters

    def initialize(viewer:, params:, page: nil)
      @viewer = viewer
      @page = page
      params = params.to_h.with_indifferent_access
      @filters = Filters.new(
        q: params[:q].to_s.strip.presence,
        status: params[:status].to_s.presence_in(Book.statuses.keys),
        genre: params[:genre].to_s.strip.presence,
        sort: params[:sort].to_s.presence_in(Book::SORTS.keys) || DEFAULTS[:sort],
        shelf: shelf_param(params[:shelf])
      )
    end

    def books
      @books ||= Book::SORTS.fetch(filters.sort).call(filters.status ? base.where(status: filters.status) : base)
        .includes(:profile, :book_shares, :shared_profiles).paginate(page: @page, per_page: PER_PAGE)
    end

    # { "reading" => 2, … } under the other filters; the "All" pill is their sum.
    def status_counts
      @status_counts ||= base.group(:status).count.transform_keys { |key| key.is_a?(Integer) ? Book.statuses.key(key) : key.to_s }
    end

    def total = status_counts.values.sum

    # The genres on the shelf being looked at (whatever status is picked).
    def genres = @genres ||= Book.genre_counts(shelf_scope.search(filters.q))

    # Housemates who shared books or their shelf with the viewer.
    def owners
      @owners ||= Profile.where(id: accessible.where.not(profile_id: viewer.id).select(:profile_id)).order(:first_name, :username).to_a
    end

    def shared? = owners.any?

    def empty_reason
      return :search if filters.q
      return :genre if filters.genre
      return :status if filters.status

      :none
    end

    private

    def accessible = Book.accessible_by(viewer)

    def shelf_scope
      case filters.shelf
      when "mine" then accessible.where(profile_id: viewer.id)
      when "everyone" then accessible
      else accessible.where(profile_id: filters.shelf.to_i)
      end
    end

    def base
      scope = shelf_scope.search(filters.q)
      filters.genre ? scope.where("? = ANY(books.genres)", filters.genre) : scope
    end

    # "mine", "everyone", or the id of a housemate who shared with the viewer.
    def shelf_param(value)
      value = value.to_s
      return value if %w[mine everyone].include?(value)
      return value if value.match?(/\A\d+\z/) && owners.any? { |owner| owner.id == value.to_i }

      DEFAULTS[:shelf]
    end
  end
end
