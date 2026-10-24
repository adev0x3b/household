import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import RecurrenceFieldsController from "../../../app/javascript/controllers/recurrence_fields_controller.js"

// The recurrence fields as Views::Occurrences::EventFields draws them.
function fields(frequency, endsBy = "never", interval = "1") {
  const option = (chosen) => (value) =>
    `<option value="${value}" ${value === chosen ? "selected" : ""}>${value}</option>`
  const end = (kind, id, counts) => `
    <div data-recurrence-fields-target="endsValue" data-ends-by="${kind}" ${counts ? `data-counts="${counts}"` : ""}>
      <input id="${id}" required>
    </div>
  `
  return `
    <div data-controller="recurrence-fields">
      <select name="event[frequency]" data-recurrence-frequency data-action="change->recurrence-fields#toggle">
        ${["none", "daily", "weekly", "monthly", "yearly"].map(option(frequency)).join("")}
      </select>
      <div data-recurrence-fields-target="details">
        <input type="number" name="event[interval]" value="${interval}"
               data-recurrence-fields-target="interval" data-action="input->recurrence-fields#toggle">
        <fieldset data-recurrence-fields-target="weeklyDays">
          <input type="checkbox" name="event[week_days][]" value="monday">
        </fieldset>
        <select name="event[ends_by]" data-recurrence-fields-target="endsBy" data-action="change->recurrence-fields#toggle">
          <option value="never" ${endsBy === "never" ? "selected" : ""}>Never</option>
          <option value="on_date" ${endsBy === "on_date" ? "selected" : ""}>On a day</option>
          <option value="after_count" ${endsBy === "after_count" ? "selected" : ""} data-recurrence-fields-target="endsCount"
                  data-days="After a number of days" data-times="After a number of times">?</option>
        </select>
        ${end("on_date", "ends")}
        ${end("after_count", "ends_after_days", "days")}
        ${end("after_count", "ends_after_times", "times")}
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
      assert.equal(input.disabled, field.hidden, `${input.id} is disabled exactly when hidden`)
      return !field.hidden
    })
    .map((field) => field.querySelector("input").id)
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

const countChoice = () => document.querySelector('[data-recurrence-fields-target="endsCount"]').textContent

function typeInterval(value) {
  const input = document.querySelector('[data-recurrence-fields-target="interval"]')
  input.value = value
  input.dispatchEvent(new Event("input", { bubbles: true }))
}

test("a series that never ends shows none of the end's fields", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily"))

  assert.deepEqual(shownEnds(), [])
})

test("a series ending on a day shows that day's field", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily", "on_date"))

  assert.deepEqual(shownEnds(), ["ends"])
})

test("a count of a series every day is in days, so twice a day isn't read as two times", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily", "after_count"))

  assert.deepEqual(shownEnds(), ["ends_after_days"])
  assert.equal(countChoice(), "After a number of days")
})

test("a count of a series that skips days is in times, and follows the repeat as it changes", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("weekly", "after_count"))

  assert.deepEqual(shownEnds(), ["ends_after_times"])
  assert.equal(countChoice(), "After a number of times")

  choose("daily")
  assert.deepEqual(shownEnds(), ["ends_after_days"])

  typeInterval("2")
  assert.deepEqual(shownEnds(), ["ends_after_times"])
  assert.equal(countChoice(), "After a number of times")
})

test("choosing how a series ends shows the one field that way asks for", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily"))

  choose("after_count", endsBy())
  assert.deepEqual(shownEnds(), ["ends_after_days"])

  choose("on_date", endsBy())
  assert.deepEqual(shownEnds(), ["ends"])

  choose("never", endsBy())
  assert.deepEqual(shownEnds(), [])
})

test("a series that stops repeating hides and disables its end, so a count left empty asks for nothing", async () => {
  page = await mount("recurrence-fields", RecurrenceFieldsController, fields("daily", "after_count"))

  choose("none")
  assert.deepEqual(shownEnds(), [])
})
