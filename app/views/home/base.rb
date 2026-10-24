# frozen_string_literal: true

# Shared shell of a home dashboard page: the section tabs, the period and
# whose data, then the page's own content, always in the same order: what
# needs attention, at most four headline figures, what's next, then one
# lazily loaded report per area.
#
# The content sits in one turbo frame that home_refresh_controller.js
# reloads after something was changed in place (a modal saved, an item
# ticked off) or, on the overview, a day changed elsewhere, so the figures
# never go stale. The frame and the lazy
# report frames inside it have refresh: :morph: a reload (or a page
# refresh after a period or member change) morphs what is there and
# reloads the reports in place, instead of swapping everything for the
# loading placeholders — which collapsed the page and threw the reader to
# the top. Links leave the frame (target: "_top"). The page wears the
# .statistics class for its layout and because the charts read their
# palette from the --stat-* properties there.
class Views::Home::Base < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  # Which page each paged list is on (`?attention_page=`…), from the request.
  LIST_PAGES = %i[attention_page agenda_upcoming_page agenda_overdue_page agenda_appointments_page].freeze

  # The page's name: its address under /home, its words under home.<key>
  # and the section whose colour it wears.
  def self.key = raise(NotImplementedError, "#{name}.key")

  # The page's lazily loaded reports (Views::Home::Reports), in order.
  def self.reports = []

  # The section's dashboard on the home reports, which the page and
  # whoever settles its "needs attention" list read.
  def self.dashboard(home) = raise(NotImplementedError, "#{name} reports on no section")

  def self.report(name) = reports.find { |report| report.report_name.to_s == name.to_s }

  # `home` is the request's Reports::Home.
  def initialize(home:, pages: {})
    @home = home
    @pages = pages
  end

  def page_title = t("home.#{page}.title")

  def view_template
    turbo_frame_tag("home-page", class: "home-page", target: "_top", refresh: :morph,
                                 data: { controller: "home-refresh", action: "calendar-subscription:changed->home-refresh#reload" }) do
      div(class: [ "statistics home", ("section--#{page}" unless page == :overview) ]) do
        page_header
        content
      end
    end
  end

  private

  def page = self.class.key

  def dashboard = self.class.dashboard(@home)

  # The page's name, its tabs, then the dates it reports on and, only when
  # data is shared, whose.
  def page_header
    div(class: "statistics__header") do
      render Components::PageHeader.new(title: t("home.#{page}.title"))
      tabs
      div(class: "statistics__heading") do
        period_selector
        member_filter if @home.audience.shared?
      end
    end
  end

  def tabs
    overview = Views::Home::Pages::OVERVIEW
    items = [ Components::NavItem.new(key: :overview, icon: overview.icon, href: root_path, label: t("home.tabs.overview")) ]
    items += Views::Home::Pages::SECTIONS.map do |key, view|
      key = key.to_sym
      Components::NavItem.new(key: key, section: key, icon: view.icon, href: home_section_path(section: key), label: t("home.tabs.#{key}"))
    end
    render Components::Tabs.new(items: items, current: page, label: t("home.tabs.label"))
  end

  def period = @home.period

  # The period is kept with the member when either changes.
  def period_selector
    render Components::Statistics::PeriodSelector.new(
      start_date: period.start_date, end_date: period.end_date,
      url: home_section_path(section: page), params: @home.audience.to_param,
    )
  end

  def member_filter
    render Views::Home::MemberFilter.new(
      audience: @home.audience, period: period, url: home_section_path(section: page),
    )
  end

  # Query params that must survive every link on the page.
  def filter_params = period.to_param.merge(@home.audience.to_param)

  # The list names itself as the page's address does, so a press that
  # settles the whole list settles this page's.
  def attention(items)
    list = { section: (page unless page == :overview), **@home.audience.to_param }
    render Views::Home::AttentionList.new(items: items, page: @pages.fetch(:attention_page, 1), viewer: @home.audience.viewer, list: list)
  end

  # A list a page at a time, in a frame of its own: its page links
  # (?<param>=) reload that frame alone and advance the URL, so a reload,
  # or home refreshing after a change, stays on the page being read.
  def paged(rows, param:, per_page:, list:)
    last = [ (rows.size.to_f / per_page).ceil, 1 ].max
    page = WillPaginate::Collection.create(@pages.fetch(param, 1).to_i.clamp(1, last), per_page, rows.size) { _1.replace(rows[_1.offset, _1.per_page]) }
    frame = "home-#{param.to_s.dasherize}"
    turbo_frame_tag(frame) do
      yield page
      render Components::Pagination.new(collection: page, turbo_frame: frame, turbo_action: "advance", param_name: param, list: list)
    end
  end

  # The page's headline figures, at most four, each worded by its key under
  # home.<page>.kpis. tiles: { key => { metric:, icon:, comparison:, footnote: } }
  def kpi_grid(tiles)
    section(class: "statistics__kpis", aria: { label: t("home.kpis.label") }) do
      tiles.each do |key, tile|
        render Components::Statistics::StatTile.new(
          metric: tile.fetch(:metric), icon: tile.fetch(:icon),
          label: t("home.#{page}.kpis.#{key}"), hint: t("home.#{page}.kpis.hints.#{key}"),
          footnote: tile[:footnote], comparison: tile.fetch(:comparison, true),
        )
      end
    end
  end

  # A report rendered with the page (what's next, as of today).
  def detail_report(name, icon:, empty: false, &)
    render Components::Statistics::Report.new(
      dom_id: "home-#{page}-#{name}", icon: icon,
      title: t("home.#{page}.#{name}.title"), description: t("home.#{page}.#{name}.description"),
    ) do
      if empty
        render Components::EmptyState.new(message: t("home.#{page}.#{name}.empty"), icon: icon)
      else
        yield
      end
    end
  end

  def target_footnote(metric) = t("home.kpis.target", target: format_figure(metric.target, :percent))

  # A money figure shows one currency; this names what moved in the others.
  def other_currencies_footnote(report)
    return if report.other_currencies.empty?

    t("home.kpis.other_currencies", amounts: report.other_currencies.map(&:to_s).join(", "))
  end

  def columns(name, *keys, numeric: []) = Components::Statistics::DataTable.columns("home.#{page}.#{name}", *keys, numeric: numeric)

  # The page's reports, each loaded lazily over the selected period and
  # member.
  def report_frames(reports = self.class.reports)
    reports.each { |report| report_frame(report) }
  end

  def report_frame(report)
    name = report.report_name
    turbo_frame_tag(
      "stat-report-#{name}",
      src: home_report_path(section: page, name: name, **filter_params),
      loading: :lazy, refresh: :morph, class: "statistics__frame",
    ) do
      div(class: "stat-report stat-report--loading", aria: { busy: "true" }) do
        span(class: "is-sr-only") { t("statistics.loading") }
      end
    end
  end

  # A row about one day of a series opens that day's modal, in place.
  def occurrence_link(row, &)
    render(Views::Home::OccurrenceLink.new(occurrence: row.occurrence), &)
  end

  def day(date) = date == @home.today ? t("home.today") : l(date, format: :day)
end
