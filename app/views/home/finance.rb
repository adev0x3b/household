# frozen_string_literal: true

# Finance: what needs attention now, the headline figures of the selected
# period, then one report per area, each read from
# Reports::Finance::Dashboard. Settlements only when the audience actually
# shares data with someone.
class Views::Home::Finance < Views::Home::Base
  def self.key = :finance
  def self.icon = "fa-sack-dollar"

  def self.dashboard(home) = home.finance

  def self.reports
    [
      Views::Home::Reports::FinanceSpending, Views::Home::Reports::FinanceIncome,
      Views::Home::Reports::FinanceSettlements
    ]
  end

  private

  def content
    income, spending, cash_flow = dashboard.income, dashboard.spending, dashboard.cash_flow
    savings_rate = cash_flow.savings_rate_metric

    attention(dashboard.attention)
    kpi_grid(
      income: { metric: income.total_metric, icon: "fa-arrow-trend-up", footnote: other_currencies_footnote(income) },
      expenses: { metric: spending.total_metric, icon: "fa-wallet", footnote: other_currencies_footnote(spending) },
      net_cash_flow: { metric: cash_flow.net_cash_flow_metric, icon: "fa-scale-balanced" },
      savings_rate: { metric: savings_rate, icon: "fa-piggy-bank", footnote: target_footnote(savings_rate) },
    )
    report_frames(shown_reports)
  end

  def shown_reports
    return self.class.reports if @home.audience.shared?

    self.class.reports - [ Views::Home::Reports::FinanceSettlements ]
  end
end
