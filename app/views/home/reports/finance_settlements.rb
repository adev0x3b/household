# frozen_string_literal: true

# Who owes whom, from the payments logged against a housemate
# (Reports::Finance::Settlements). The Finance page shows it only when
# the audience shares data with someone.
class Views::Home::Reports::FinanceSettlements < Views::Home::Reports::Base
  def self.page = :finance
  def self.report_name = :settlements

  private

  def icon = "fa-right-left"

  def report = @home.finance.settlements

  def content
    render Components::Statistics::DataTable.new(
      caption: t("home.finance.settlements.table_caption"),
      columns: columns(:debtor, :creditor, :amount, numeric: %i[amount]),
    ) do |table|
      names = Profiles::DisplayNames.new(report.balances.flat_map { [ _1.debtor, _1.creditor ] })
      report.balances.each do |balance|
        table.row do
          table.cell { names.of(balance.debtor) }
          table.cell { names.of(balance.creditor) }
          table.cell { balance.money.to_s }
        end
      end
    end
  end
end
