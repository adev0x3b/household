# frozen_string_literal: true

# One report on a home page, loaded lazily over the page's period and
# member: the page leaves a turbo frame for it ("stat-report-<name>") and
# this answers with the same frame. A report view says which page it is on
# and its name, which give its frame's id, the address that loads it and
# its words, under home.<page>.<name>; then its icon, the report it draws
# and its content, and shows an empty state when the report has nothing to
# show (#any?).
class Views::Home::Reports::Base < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  def self.page = raise(NotImplementedError, "#{name}.page")
  def self.report_name = raise(NotImplementedError, "#{name}.report_name")

  # `home` is the page's Reports::Home.
  def initialize(home:)
    @home = home
  end

  def view_template
    turbo_frame_tag("stat-report-#{report_name}") do
      render Components::Statistics::Report.new(
        dom_id: "stat-#{report_name}", icon: icon,
        title: t("#{scope}.title"), description: t("#{scope}.description"),
      ) do
        any? ? content : render(Components::EmptyState.new(message: t("#{scope}.empty"), icon: icon))
      end
    end
  end

  private

  def report_name = self.class.report_name

  def scope = "home.#{self.class.page}.#{report_name}"

  def any? = report.any?

  def date(value) = value ? l(value, format: :short) : format_figure(nil, :count)

  def columns(*keys, numeric: []) = Components::Statistics::DataTable.columns(scope, *keys, numeric: numeric)

  def chart(chart, **) = render(Components::Statistics::Chart.new(chart: chart, **))

  def subtitle(key) = h3(class: "stat-report__subtitle") { t("#{scope}.#{key}") }
end
