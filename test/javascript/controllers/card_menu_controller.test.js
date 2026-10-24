import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import CardMenuController from "../../../app/javascript/controllers/card_menu_controller.js"

// A delete's two wordings, as Views::Calendar::CardMenu draws them.
function entry(scope, label, confirm) {
  return `
    <button type="submit" name="scope" value="${scope}" data-card-menu-target="entry"
            data-turbo-confirm="${confirm}" data-label="${label}" data-confirm="${confirm}"
            data-ask-label="Ask %{name} to ${label.toLowerCase()}" data-ask-confirm="Ask %{name} to ${confirm.toLowerCase()}">
      <i class="fa-trash"></i><span>${label}</span>
    </button>
  `
}

// Two cards' "more" buttons and the page's one menu, as
// Views::Calendar::DayMenus draws them: the viewer's own repeating series,
// and a day of Sam's whose delete waits for Sam.
const PAGE = `
  <div data-controller="card-menu">
    <button id="bins" aria-expanded="false" data-action="card-menu#open"
            data-card-menu-url-param="/events/1/days/2027-03-08" data-card-menu-repeats-param="true">More</button>
    <button id="plumber" aria-expanded="false" data-action="card-menu#open"
            data-card-menu-url-param="/events/2/days/2027-03-09" data-card-menu-repeats-param="false"
            data-card-menu-owner-param="Sam">More</button>
    <div id="card_menu" role="group" data-card-menu-target="menu"
         data-action="turbo:before-morph-element->card-menu#holdWhileOpen">
      <form method="post" data-card-menu-target="form" data-action="submit->card-menu#chosen">
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
const entryFor = (scope) => menu().querySelector(`[value="${scope}"]`)
const words = (scope) => [entryFor(scope).querySelector("span").textContent, entryFor(scope).dataset.turboConfirm]

test("a repeating series' more opens the menu on its day, both deletes in the viewer's words", () => {
  press("bins")

  assert.equal(shown(), true)
  assert.equal(menu().querySelector("form").getAttribute("action"), "/events/1/days/2027-03-08")
  assert.equal(entryFor("series").hidden, false)
  assert.deepEqual(words("occurrence"), ["Delete this day", "Delete this day?"])
  assert.equal(document.getElementById("bins").getAttribute("aria-expanded"), "true")
  assert.equal(
    document.activeElement,
    entryFor("occurrence"),
    "focus goes into the menu, which is elsewhere on the page"
  )
})

test("a day of a series that doesn't repeat offers the day alone, worded as asking its owner", () => {
  press("plumber")

  assert.equal(entryFor("series").hidden, true)
  assert.equal(menu().querySelector("form").getAttribute("action"), "/events/2/days/2027-03-09")
  assert.deepEqual(words("occurrence"), ["Ask Sam to delete this day", "Ask Sam to delete this day?"])
})

test("moving to the viewer's own card words the menu as theirs again", () => {
  press("plumber")
  press("bins")

  assert.deepEqual(words("series"), ["Delete the whole series", "Delete every day of this series?"])
  assert.equal(document.getElementById("plumber").getAttribute("aria-expanded"), "false")
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

test("a delete chosen folds the menu before its question, with focus back on the card's button", () => {
  press("bins")
  menu()
    .querySelector("form")
    .dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

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
