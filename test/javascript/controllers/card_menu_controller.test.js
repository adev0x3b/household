import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import CardMenuController from "../../../app/javascript/controllers/card_menu_controller.js"

// A status's two wordings, as Views::Calendar::CardMenu draws them.
function statusEntry(status, label) {
  return `
    <button type="submit" name="status" value="${status}" class="item-menu__entry" data-card-menu-target="entry"
            data-label="${label}" data-ask-label="Ask %{name} to ${label.toLowerCase()}">
      <i class="fa-forward"></i><span>${label}</span>
    </button>
  `
}

// A delete's two wordings.
function entry(scope, label, confirm) {
  return `
    <button type="submit" name="scope" value="${scope}" data-card-menu-target="entry"
            data-turbo-confirm="${confirm}" data-label="${label}" data-confirm="${confirm}"
            data-ask-label="Ask %{name} to ${label.toLowerCase()}" data-ask-confirm="Ask %{name} to ${confirm.toLowerCase()}">
      <i class="fa-trash"></i><span>${label}</span>
    </button>
  `
}

// Three cards' "more" buttons and the page's one menu, as
// Views::Calendar::DayMenus draws them: the viewer's own repeating series,
// a day of Sam's whose presses wait for Sam, and a done day of Sam's the
// viewer may delete but whose status is the circle's.
const PAGE = `
  <div data-controller="card-menu">
    <button id="bins" aria-expanded="false" data-action="card-menu#open"
            data-card-menu-delete-url-param="/events/1/days/2027-03-08" data-card-menu-repeats-param="true"
            data-card-menu-status-url-param="/events/1/days/2027-03-08/status"
            data-card-menu-statuses-param='["skipped","cancelled"]'>More</button>
    <button id="plumber" aria-expanded="false" data-action="card-menu#open"
            data-card-menu-delete-url-param="/events/2/days/2027-03-09" data-card-menu-repeats-param="false"
            data-card-menu-delete-owner-param="Sam" data-card-menu-status-url-param="/events/2/days/2027-03-09/status"
            data-card-menu-statuses-param='["cancelled","pending"]' data-card-menu-status-owner-param="Sam">More</button>
    <button id="laundry" aria-expanded="false" data-action="card-menu#open"
            data-card-menu-delete-url-param="/events/3/days/2027-03-10" data-card-menu-repeats-param="false">More</button>
    <div id="card_menu" role="group" data-card-menu-target="menu"
         data-action="turbo:before-morph-element->card-menu#holdWhileOpen">
      <form method="post" data-card-menu-target="statusForm" data-action="submit->card-menu#chosen">
        <input type="hidden" name="_method" value="patch">
        ${statusEntry("skipped", "Skip this day")}
        ${statusEntry("cancelled", "Cancel this day")}
        ${statusEntry("pending", "Set back to pending")}
      </form>
      <form method="post" data-card-menu-target="deleteForm" data-action="submit->card-menu#chosen">
        <input type="hidden" name="_method" value="delete">
        ${entry("occurrence", "Delete this day", "Delete this day?")}
        ${entry("series", "Delete the whole series", "Delete every day of this series?")}
      </form>
    </div>
  </div>
`

let page
beforeEach(async () => {
  page = await mount("card-menu", CardMenuController, PAGE)
  // jsdom lays nothing out: the menu is what is seen wherever it is placed.
  document.elementFromPoint = () => menu()
})
afterEach(() => page.stop())

const menu = () => document.getElementById("card_menu")
const press = (id) => document.getElementById(id).click()
const shown = () => menu().classList.contains("is-open")
const statusForm = () => menu().querySelectorAll("form")[0]
const deleteForm = () => menu().querySelectorAll("form")[1]
const entryFor = (value) => menu().querySelector(`[value="${value}"]`)
const words = (scope) => [entryFor(scope).querySelector("span").textContent, entryFor(scope).dataset.turboConfirm]
const statusesShown = () =>
  [...statusForm().querySelectorAll("button")].filter((entry) => !entry.hidden).map((entry) => entry.value)

test("a repeating series' more opens the menu on its day, its statuses and both deletes in the viewer's words", () => {
  press("bins")

  assert.equal(shown(), true)
  assert.equal(statusForm().getAttribute("action"), "/events/1/days/2027-03-08/status")
  assert.deepEqual(statusesShown(), ["skipped", "cancelled"])
  assert.equal(entryFor("skipped").querySelector("span").textContent, "Skip this day")
  assert.equal(deleteForm().getAttribute("action"), "/events/1/days/2027-03-08")
  assert.equal(entryFor("series").hidden, false)
  assert.deepEqual(words("occurrence"), ["Delete this day", "Delete this day?"])
  assert.equal(document.getElementById("bins").getAttribute("aria-expanded"), "true")
  assert.equal(document.activeElement, entryFor("skipped"), "focus goes into the menu, which is elsewhere on the page")
})

test("a day of a series that doesn't repeat offers the day alone, every press worded as asking its owner", () => {
  press("plumber")

  assert.deepEqual(statusesShown(), ["cancelled", "pending"])
  assert.equal(entryFor("pending").querySelector("span").textContent, "Ask Sam to set back to pending")
  assert.equal(entryFor("series").hidden, true)
  assert.equal(deleteForm().getAttribute("action"), "/events/2/days/2027-03-09")
  assert.deepEqual(words("occurrence"), ["Ask Sam to delete this day", "Ask Sam to delete this day?"])
})

test("moving to the viewer's own card words the menu as theirs again", () => {
  press("plumber")
  press("bins")

  assert.equal(entryFor("cancelled").querySelector("span").textContent, "Cancel this day")
  assert.deepEqual(words("series"), ["Delete the whole series", "Delete every day of this series?"])
  assert.equal(document.getElementById("plumber").getAttribute("aria-expanded"), "false")
})

test("a card that gives no status address hides the statuses, and the focus goes to its first delete", () => {
  press("laundry")

  assert.equal(statusForm().hidden, true)
  assert.equal(deleteForm().hidden, false)
  assert.equal(document.activeElement, entryFor("occurrence"))
})

test("a second press on the same button closes the menu, and Escape closes it with focus back on the button", () => {
  press("bins")
  press("bins")
  assert.equal(shown(), false)

  press("bins")
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
  assert.equal(shown(), false)
  assert.equal(document.activeElement, document.getElementById("bins"))
})

test("a click elsewhere closes it", () => {
  press("bins")
  document.body.click()

  assert.equal(shown(), false)
})

test("a scroll that leaves the card's button where it was keeps the menu, and one that moves it closes it", () => {
  const button = document.getElementById("bins")
  let top = 100
  button.getBoundingClientRect = () => ({ top, bottom: top + 20, left: 330, right: 350, width: 20, height: 20 })
  const scroll = () => document.dispatchEvent(new Event("scroll"))

  press("bins")
  scroll()
  assert.equal(shown(), true, "scrolled away and back before the event came")

  top = 60
  scroll()
  assert.equal(shown(), false)
})

test("a press chosen folds the menu, before a delete's question, with focus back on the card's button", () => {
  press("bins")
  deleteForm().dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

  assert.equal(shown(), false)
  assert.equal(document.activeElement, document.getElementById("bins"))
})

test("a page refresh leaves the menu as it is while open, and morphs it once closed", () => {
  const morph = () => {
    const event = new CustomEvent("turbo:before-morph-element", { bubbles: true, cancelable: true })
    menu().dispatchEvent(event)
    return event.defaultPrevented
  }

  press("bins")
  assert.equal(morph(), true)
  press("bins")
  assert.equal(morph(), false)
})
