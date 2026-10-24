import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import DayAddController from "../../../app/javascript/controllers/day_add_controller.js"

// Two days' "+" and the page's one menu of the kinds, as
// Views::Calendar::DayMenus draws them.
const PAGE = `
  <div data-controller="day-add">
    <button id="monday" aria-expanded="false" data-action="day-add#open" data-day-add-date-param="2027-03-08">+</button>
    <button id="tuesday" aria-expanded="false" data-action="day-add#open" data-day-add-date-param="2027-03-09">+</button>
    <div id="day_add_menu" role="group" data-day-add-target="menu"
         data-action="turbo:before-morph-element->day-add#holdWhileOpen">
      <form method="get" data-turbo-stream data-action="submit->day-add#chosen">
        <input type="hidden" name="date" data-day-add-target="date">
        <button type="submit" formaction="/tasks/new">Task</button>
        <button type="submit" formaction="/meals/new">Meal</button>
      </form>
    </div>
  </div>
`

let page
beforeEach(async () => {
  page = await mount("day-add", DayAddController, PAGE)
  document.elementFromPoint = () => menu() // jsdom lays nothing out
})
afterEach(() => page.stop())

const menu = () => document.getElementById("day_add_menu")
const press = (id) => document.getElementById(id).click()
const day = () => menu().querySelector('[name="date"]').value
const shown = () => menu().classList.contains("is-open")

test("a day's + opens the menu for its day, which each kind's form is sent", () => {
  press("monday")
  assert.equal(shown(), true)
  assert.equal(day(), "2027-03-08")

  press("tuesday")
  assert.equal(shown(), true)
  assert.equal(day(), "2027-03-09")
  assert.equal(document.getElementById("monday").getAttribute("aria-expanded"), "false")
})

test("a second press on the same + closes it", () => {
  press("monday")
  press("monday")

  assert.equal(shown(), false)
})

test("a kind chosen folds the menu as its form opens, with focus back on the +", () => {
  press("monday")
  menu()
    .querySelector("form")
    .dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

  assert.equal(shown(), false)
  assert.equal(document.activeElement, document.getElementById("monday"))
})
