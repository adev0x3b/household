# frozen_string_literal: true

require "application_system_test_case"

# A payment between housemates is one series with two readers: the payer
# sees what was spent, the housemate it was paid to the same money coming
# in. The form shows only the counterparty field in use, and asks the
# method once an amount is typed (transaction_form_controller.js).
class PaymentsTest < ApplicationSystemTestCase
  test "a payment to a housemate is spent on the payer's calendar and received on the housemate's" do
    alice, bob = profiles(:alice), profiles(:bob)
    sixty = Reports::Money.new(cents: 60_00, currency: households(:example).currency)

    sign_in alice
    visit calendar_path
    add_to_day(Date.current, :transaction)
    within(".modal") do
      fill_in I18n.t("transactions.form.title_label"), with: "Concert tickets"
      fill_in I18n.t("transactions.form.amount_label"), with: "60"
      select I18n.t("transactions.kind.expense"), from: I18n.t("transactions.form.kind_label")
      select I18n.t("transactions.category.entertainment"), from: I18n.t("transactions.form.category_label")
      assert_no_field I18n.t("transactions.form.counterparty_profile_label")
      select I18n.t("transactions.form.counterparty_mode_profile"), from: I18n.t("transactions.form.counterparty_label")
      assert_no_field I18n.t("transactions.form.counterparty_text_label")
      select bob.display_name, from: I18n.t("transactions.form.counterparty_profile_label")
      select I18n.t("transactions.payment_method.bank_transfer"), from: I18n.t("transactions.form.payment_method_label")
      assert_accessible "a new payment to a housemate"
      click_on I18n.t("transactions.form.create")
    end
    assert_text I18n.t("transactions.notices.created")

    within_day(Date.current) do
      within(".transaction-card", text: "Concert tickets") do
        assert_text "-#{sixty}"
        assert_text bob.display_name
        assert_no_selector ".transaction-card__kind" # spending is told by its sign; only money coming in is named
      end
    end

    using_session(:bob) do
      sign_in bob
      visit calendar_path
      within_day(Date.current) do
        within(".transaction-card", text: "Concert tickets") do
          assert_text "+#{sixty}"
          assert_selector ".transaction-card__kind", text: /#{I18n.t("transactions.kind.income")}/i # drawn in capitals
          assert_text alice.display_name
        end
      end
    end
  end
end
