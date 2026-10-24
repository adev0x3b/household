# frozen_string_literal: true

# Healthcare: what needs attention now, the headline figures of the
# selected period, then one report per area, each read from
# Reports::Healthcare::Dashboard.
class Views::Home::Healthcare < Views::Home::Base
  def self.key = :healthcare
  def self.icon = "fa-heart-pulse"

  def self.dashboard(home) = home.healthcare

  def self.reports
    [
      Views::Home::Reports::HealthcareMedications, Views::Home::Reports::HealthcareAppointments,
      Views::Home::Reports::HealthcareLabs, Views::Home::Reports::HealthcareSpending,
      Views::Home::Reports::HealthcareSupplies
    ]
  end

  private

  def content
    adherence = dashboard.medications.adherence_metric

    attention(dashboard.attention)
    kpi_grid(
      adherence: { metric: adherence, icon: "fa-pills", footnote: target_footnote(adherence) },
      missed_doses: { metric: dashboard.medications.missed_metric, icon: "fa-calendar-xmark" },
      spend: { metric: dashboard.spending.spend_metric, icon: "fa-wallet", footnote: spend_footnote },
      out_of_range_labs: { metric: dashboard.labs.out_of_range_metric, icon: "fa-flask", footnote: critical_footnote },
    )
    report_frames
  end

  # What is still scheduled to be spent in the period, and what was spent
  # in other currencies.
  def spend_footnote
    spending = dashboard.spending
    scheduled = spending.scheduled
    parts = [ (t("home.healthcare.kpis.footnotes.scheduled", amount: scheduled) if scheduled.positive?) ]
    parts << other_currencies_footnote(spending)
    parts.compact.join(" · ").presence
  end

  def critical_footnote
    critical = dashboard.labs.critical_count
    t("home.healthcare.kpis.footnotes.critical", count: critical) if critical.positive?
  end
end
