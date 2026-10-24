import { Controller } from "@hotwired/stimulus"

// A payment's form, and the cost fields inside another record's form
// (Views::Transactions::CostFields). The counterparty, where it is asked,
// is typed or picked among the housemates, and only the field in use is
// shown and sent. Inside another record's form, logging the cost is
// optional, so the method is required only once an amount is typed. A saved
// payment's "done" status is worded by which way the money goes, so it
// follows the kind as it is changed.
export default class extends Controller {
  static targets = [
    "amount",
    "counterpartyMode",
    "counterpartyTextSection",
    "counterpartyTextInput",
    "counterpartyProfileSection",
    "counterpartyProfileSelect",
    "paymentMethod",
    "kind",
    "doneOption"
  ]

  connect() {
    this.refresh()
  }

  // A fee's or a bill's cost fields ask no counterparty.
  syncCounterpartyMode() {
    if (!this.hasCounterpartyModeTarget) return

    const profile = this.counterpartyModeTarget.value === "profile"

    this.counterpartyTextSectionTarget.hidden = profile
    this.counterpartyTextInputTarget.disabled = profile
    this.counterpartyProfileSectionTarget.hidden = !profile
    this.counterpartyProfileSelectTarget.disabled = !profile
  }

  refresh() {
    this.syncCounterpartyMode()
    this.requirePaymentMethod()
    this.wordDoneStatus()
  }

  // Both wordings travel on the option, drawn by the form, so the page
  // needs no translations of its own.
  wordDoneStatus() {
    if (!this.hasKindTarget) return

    const income = this.kindTarget.value === "income"
    this.doneOptionTargets.forEach((option) => {
      option.textContent = income ? option.dataset.receivedLabel : option.dataset.paidLabel
    })
  }

  // The payment's own form asks the method with its other fields; the cost
  // fields' select is marked required for the modal's form to wait on,
  // and runs before it on the same event, being inside it.
  requirePaymentMethod() {
    if (!this.hasPaymentMethodTarget || !this.hasAmountTarget) return

    this.paymentMethodTarget.required = this.amountTarget.value.trim() !== ""
  }
}
