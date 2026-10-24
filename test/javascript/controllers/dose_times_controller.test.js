import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import DoseTimesController from "../../../app/javascript/controllers/dose_times_controller.js"

// The standard times the server hands the form, cut to three doses a day.
const DEFAULTS = { 1: ["08:00"], 2: ["08:00", "20:00"], 3: ["08:00", "14:00", "20:00"] }

// A dose as Views::Medications::DoseTimesFields draws it: an anchor, or a
// clock time with "custom" chosen, or neither for the template's blank row.
function row({ anchor = null, time = null } = {}) {
  const option = (value) =>
    `<option value="${value}" ${value === (anchor ?? "custom") ? "selected" : ""}>${value}</option>`
  return `
    <div data-dose-times-target="row">
      <select data-dose-times-target="anchor" data-action="change->dose-times#sync">
        ${["CM", "CD", "CV", "HS", "custom"].map(option).join("")}
      </select>
      <input type="time" value="${time ?? ""}" data-dose-times-target="time"
             data-action="input->dose-times#sync change->dose-times#sync">
      <input type="hidden" name="event[slots][]" value="${anchor ?? time ?? ""}" data-dose-times-target="value">
      <button type="button" data-action="dose-times#remove"><i class="fa-xmark"></i></button>
    </div>
  `
}

function form(rows, { max = 3 } = {}) {
  return `
    <fieldset data-controller="dose-times" data-dose-times-defaults-value='${JSON.stringify(DEFAULTS)}'
              data-dose-times-max-value="${max}">
      <button type="button" class="fewer" data-action="dose-times#decrement">−</button>
      <span data-dose-times-target="count">${rows.length}</span>
      <button type="button" class="more" data-action="dose-times#increment">+</button>
      <div data-dose-times-target="rows">${rows.map(row).join("")}</div>
      <template data-dose-times-target="template">${row()}</template>
    </fieldset>
  `
}

let page
afterEach(() => page.stop())

const rows = () => Array.from(document.querySelectorAll('[data-dose-times-target="rows"] > div'))
const sent = () => rows().map((element) => element.querySelector('[name="event[slots][]"]').value)
const count = () => document.querySelector('[data-dose-times-target="count"]').textContent
const press = (selector) => document.querySelector(selector).click()

function choose(element, value) {
  element.value = value
  element.dispatchEvent(new Event("change", { bubbles: true }))
}

test("a dose at an anchor sends the anchor, and its clock is hidden and left out", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ anchor: "CV" }]))

  const time = rows()[0].querySelector('input[type="time"]')
  assert.deepEqual(sent(), ["CV"])
  assert.equal(time.hidden, true)
  assert.equal(time.disabled, true)
})

test("a dose at a clock time sends the time typed", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ time: "07:30" }]))
  const time = rows()[0].querySelector('input[type="time"]')

  time.value = "09:15"
  time.dispatchEvent(new Event("input", { bubbles: true }))

  assert.equal(time.hidden, false)
  assert.deepEqual(sent(), ["09:15"])
})

test("switching a dose between an anchor and a clock time changes what it sends", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ time: "07:30" }]))
  const select = rows()[0].querySelector("select")

  choose(select, "HS")
  assert.deepEqual(sent(), ["HS"])

  choose(select, "custom")
  assert.deepEqual(sent(), ["07:30"])
})

test("the first dose added is proposed at the standard time for one a day", async () => {
  page = await mount("dose-times", DoseTimesController, form([]))

  press(".more")

  assert.deepEqual(sent(), ["08:00"])
  assert.equal(count(), "1")
  assert.equal(rows()[0].querySelector("select").value, "custom")
})

test("a dose added takes the standard time for that many a day that no dose has yet", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ time: "08:00" }]))

  press(".more")

  assert.deepEqual(sent(), ["08:00", "20:00"])
})

test("adding a dose leaves the doses already set as they are", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ anchor: "CM" }, { time: "13:00" }]))

  press(".more")

  assert.deepEqual(sent(), ["CM", "13:00", "08:00"])
  assert.equal(count(), "3")
})

test("no dose is added past the most a day", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ time: "08:00" }, { time: "20:00" }], { max: 2 }))

  press(".more")

  assert.deepEqual(sent(), ["08:00", "20:00"])
  assert.equal(count(), "2")
})

test("taking a dose away removes the last one", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ time: "08:00" }, { time: "20:00" }]))

  press(".fewer")

  assert.deepEqual(sent(), ["08:00"])
  assert.equal(count(), "1")
})

test("taking a dose away from none leaves none", async () => {
  page = await mount("dose-times", DoseTimesController, form([]))

  press(".fewer")

  assert.deepEqual(sent(), [])
  assert.equal(count(), "0")
})

test("a dose's own button removes that dose, from its icon too", async () => {
  page = await mount("dose-times", DoseTimesController, form([{ time: "08:00" }, { time: "14:00" }, { time: "20:00" }]))

  rows()[1].querySelector("i").click()

  assert.deepEqual(sent(), ["08:00", "20:00"])
  assert.equal(count(), "2")
})
