import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import RecurrenceFieldsController from "../../../app/javascript/controllers/recurrence_fields_controller.js"

// The recurrence fields as Views::Occurrences::EventFields draws them.
function fields(frequency) {
  const option = (value) => `<option value="${value}" ${value === frequency ? "selected" : ""}>${value}</option>`
  return `
    <div data-controller="recurrence-fields">
      <select name="event[frequency]" data-recurrence-frequency data-action="change->recurrence-fields#toggle">
        ${["none", "daily", "weekly", "monthly", "yearly"].map(option).join("")}
      </select>
      <div data-recurrence-fields-target="details">
        <input type="number" name="event[interval]" value="1">
        <fieldset data-recurrence-fields-target="weeklyDays">
          <input type="checkbox" name="event[week_days][]" value="monday">
        </fieldset>
      </div>
    </div>
  `
}

let page
afterEach(() => page.stop())

const details = () => document.querySelector('[data-recurrence-fields-target="details"]')
const weeklyDays = () => document.querySelector('[data-recurrence-fields-target="weeklyDays"]')

function choose(frequency) {
  const select = document.querySelector("[data-recurrence-frequency]")
  select.value = frequency
  select.dispatchEvent(new Event("change", { bubbles: true }))
}

test("a series that doesn't repeat shows neither the interval nor the days", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("none"))

  assert.equal(details().hidden, true)
  assert.equal(weeklyDays().hidden, true)
})

test("a weekly series shows the interval and the days of the week", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("weekly"))

  assert.equal(details().hidden, false)
  assert.equal(weeklyDays().hidden, false)
})

test("a series repeating by another frequency shows the interval alone", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("monthly"))

  assert.equal(details().hidden, false)
  assert.equal(weeklyDays().hidden, true)
})

test("choosing another frequency shows the fields that apply to it", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("none"))

  choose("weekly")
  assert.equal(details().hidden, false)
  assert.equal(weeklyDays().hidden, false)

  choose("daily")
  assert.equal(weeklyDays().hidden, true)

  choose("none")
  assert.equal(details().hidden, true)
})
