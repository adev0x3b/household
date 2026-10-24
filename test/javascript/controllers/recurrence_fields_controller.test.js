import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import RecurrenceFieldsController from "../../../app/javascript/controllers/recurrence_fields_controller.js"

// The recurrence fields as Views::Occurrences::EventFields draws them.
function fields(frequency, endsBy = "never") {
  const option = (chosen) => (value) =>
    `<option value="${value}" ${value === chosen ? "selected" : ""}>${value}</option>`
  const end = (kind, type, name) => `
    <div data-recurrence-fields-target="endsValue" data-ends-by="${kind}">
      <input type="${type}" name="event[${name}]" required>
    </div>
  `
  return `
    <div data-controller="recurrence-fields">
      <select name="event[frequency]" data-recurrence-frequency data-action="change->recurrence-fields#toggle">
        ${["none", "daily", "weekly", "monthly", "yearly"].map(option(frequency)).join("")}
      </select>
      <div data-recurrence-fields-target="details">
        <input type="number" name="event[interval]" value="1">
        <fieldset data-recurrence-fields-target="weeklyDays">
          <input type="checkbox" name="event[week_days][]" value="monday">
        </fieldset>
        <select name="event[ends_by]" data-recurrence-fields-target="endsBy" data-action="change->recurrence-fields#toggle">
          ${["never", "on_date", "after_days", "after_times"].map(option(endsBy)).join("")}
        </select>
        ${end("on_date", "date", "ends")}
        ${end("after_days", "number", "ends_after_days")}
        ${end("after_times", "number", "ends_after_times")}
      </div>
    </div>
  `
}

let page
afterEach(() => page.stop())

const details = () => document.querySelector('[data-recurrence-fields-target="details"]')
const weeklyDays = () => document.querySelector('[data-recurrence-fields-target="weeklyDays"]')

// The end's fields that are shown, by the name each sends; a field
// that is hidden must be disabled too, or it would still be required.
function shownEnds() {
  return [...document.querySelectorAll('[data-recurrence-fields-target="endsValue"]')]
    .filter((field) => {
      const input = field.querySelector("input")
      assert.equal(input.disabled, field.hidden, `${input.name} is disabled exactly when hidden`)
      return !field.hidden
    })
    .map((field) => field.querySelector("input").name)
}

function choose(value, select = document.querySelector("[data-recurrence-frequency]")) {
  select.value = value
  select.dispatchEvent(new Event("change", { bubbles: true }))
}

const endsBy = () => document.querySelector('[data-recurrence-fields-target="endsBy"]')

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

test("a series that never ends shows none of the end's fields", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily"))

  assert.deepEqual(shownEnds(), [])
})

test("a series ending on a day shows that day's field, filled in from the start", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily", "on_date"))

  assert.deepEqual(shownEnds(), ["event[ends]"])
})

test("choosing how a series ends shows the one field that way asks for", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily"))

  choose("after_days", endsBy())
  assert.deepEqual(shownEnds(), ["event[ends_after_days]"])

  choose("after_times", endsBy())
  assert.deepEqual(shownEnds(), ["event[ends_after_times]"])

  choose("never", endsBy())
  assert.deepEqual(shownEnds(), [])
})

test("a series that stops repeating hides and disables its end, so a count left empty asks for nothing", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily", "after_days"))

  choose("none")
  assert.deepEqual(shownEnds(), [])
})
