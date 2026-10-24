import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import TransactionFormController from "../../../app/javascript/controllers/transaction_form_controller.js"

// A cost's fields inside another record's form, as
// Views::Transactions::CostFields draws them; a fee's or a bill's ask no
// counterparty.
function costFields({ amount = "", mode = "text", counterparty = true } = {}) {
  const profile = mode === "profile"
  return `
    <div data-controller="transaction-form"
         data-action="input->transaction-form#refresh change->transaction-form#refresh">
      <input type="number" name="transaction[amount]" value="${amount}" data-transaction-form-target="amount">
      ${counterparty ? counterpartyFields(profile) : ""}
      <select name="transaction[payment_method]" data-transaction-form-target="paymentMethod">
        <option value=""></option>
        <option value="card">card</option>
      </select>
    </div>
  `
}

function counterpartyFields(profile) {
  return `
    <select name="transaction[counterparty_mode]" data-transaction-form-target="counterpartyMode"
            data-action="change->transaction-form#syncCounterpartyMode">
      <option value="text" ${profile ? "" : "selected"}>text</option>
      <option value="profile" ${profile ? "selected" : ""}>profile</option>
    </select>
    <div data-transaction-form-target="counterpartyTextSection" ${profile ? "hidden" : ""}>
      <input type="text" name="transaction[counterparty]" data-transaction-form-target="counterpartyTextInput"
             ${profile ? "disabled" : ""}>
    </div>
    <div data-transaction-form-target="counterpartyProfileSection" ${profile ? "" : "hidden"}>
      <select name="transaction[counterparty_profile_id]" data-transaction-form-target="counterpartyProfileSelect"
              ${profile ? "" : "disabled"}>
        <option value="">—</option>
      </select>
    </div>
  `
}

let page
afterEach(() => page.stop())

const field = (name) => document.querySelector(`[name="transaction[${name}]"]`)
const section = (target) => document.querySelector(`[data-transaction-form-target="${target}"]`)

function type(input, value) {
  input.value = value
  input.dispatchEvent(new Event("input", { bubbles: true }))
}

function choose(select, value) {
  select.value = value
  select.dispatchEvent(new Event("change", { bubbles: true }))
}

test("a counterparty typed by name shows and sends the name alone", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields({ mode: "text" }))

  assert.equal(section("counterpartyTextSection").hidden, false)
  assert.equal(field("counterparty").disabled, false)
  assert.equal(section("counterpartyProfileSection").hidden, true)
  assert.equal(field("counterparty_profile_id").disabled, true)
})

test("a housemate as the counterparty shows and sends the pick alone", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields({ mode: "text" }))

  choose(field("counterparty_mode"), "profile")

  assert.equal(section("counterpartyTextSection").hidden, true)
  assert.equal(field("counterparty").disabled, true)
  assert.equal(section("counterpartyProfileSection").hidden, false)
  assert.equal(field("counterparty_profile_id").disabled, false)
})

test("going back to a name sends the name again", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields({ mode: "profile" }))

  choose(field("counterparty_mode"), "text")

  assert.equal(field("counterparty").disabled, false)
  assert.equal(field("counterparty_profile_id").disabled, true)
})

test("a cost with no amount asks for no payment method", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields())

  assert.equal(field("payment_method").required, false)
})

test("a cost asks for its payment method once an amount is typed, and not after it is cleared", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields())

  type(field("amount"), "12.50")
  assert.equal(field("payment_method").required, true)

  type(field("amount"), "")
  assert.equal(field("payment_method").required, false)
})

test("a cost already logged asks for its payment method from the start", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields({ amount: "40" }))

  assert.equal(field("payment_method").required, true)
})

test("a fee's cost fields, which ask no counterparty, still ask for the method", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields({ counterparty: false }))

  type(field("amount"), "30")

  assert.equal(field("payment_method").required, true)
})

// A saved payment's form: its kind and the status that says when it is done.
function paymentForm(kind) {
  return `
    <div data-controller="transaction-form"
         data-action="input->transaction-form#refresh change->transaction-form#refresh">
      <select name="transaction[kind]" data-transaction-form-target="kind">
        <option value="expense" ${kind === "expense" ? "selected" : ""}>expense</option>
        <option value="income" ${kind === "income" ? "selected" : ""}>income</option>
      </select>
      <select name="transaction[status]">
        <option value="pending">Pending</option>
        <option value="completed" data-transaction-form-target="doneOption"
                data-paid-label="Paid" data-received-label="Received">${kind === "income" ? "Received" : "Paid"}</option>
      </select>
    </div>
  `
}

const doneOption = () => document.querySelector("option[value=completed]")

test("the done status follows the kind as it is changed, before anything is saved", async () => {
  page = await mount("transaction-form", TransactionFormController, paymentForm("expense"))
  assert.equal(doneOption().textContent, "Paid")

  choose(document.querySelector("[name='transaction[kind]']"), "income")
  assert.equal(doneOption().textContent, "Received")

  choose(document.querySelector("[name='transaction[kind]']"), "expense")
  assert.equal(doneOption().textContent, "Paid")
})

test("a form without a kind, such as a cost's fields, leaves the status alone", async () => {
  page = await mount("transaction-form", TransactionFormController, costFields())

  assert.equal(document.querySelectorAll("[data-transaction-form-target=doneOption]").length, 0)
})
