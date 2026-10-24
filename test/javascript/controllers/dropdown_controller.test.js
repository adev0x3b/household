import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import DropdownController from "../../../app/javascript/controllers/dropdown_controller.js"

// An item's "more" menu, as Components::ItemMenu draws it, beside something
// else on the page to click.
const MENU = `
  <div class="item-menu" data-controller="dropdown">
    <button id="more" aria-expanded="false" data-action="click->dropdown#toggle" data-dropdown-target="toggler">More</button>
    <div class="item-menu__menu" data-dropdown-target="menu">
      <a id="edit" href="#" data-action="click->dropdown#close">Edit</a>
    </div>
  </div>
  <input id="elsewhere">
`

let mounted

beforeEach(async () => {
  mounted = await mount("dropdown", DropdownController, MENU)
})

afterEach(() => mounted.stop())

const byId = (id) => document.getElementById(id)

function openWithFocusOnEntry() {
  byId("more").click()
  byId("edit").focus()
}

test("choosing an entry folds the menu and gives the focus back to its button", () => {
  openWithFocusOnEntry()

  byId("edit").click()

  assert.equal(mounted.controller.isOpen, false)
  assert.equal(document.activeElement.id, "more")
})

test("Escape inside the menu gives the focus back to its button too", () => {
  openWithFocusOnEntry()

  byId("edit").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))

  assert.equal(mounted.controller.isOpen, false)
  assert.equal(document.activeElement.id, "more")
})

test("a click elsewhere folds the menu and leaves the focus where it went", () => {
  byId("more").click()
  byId("elsewhere").focus()

  byId("elsewhere").click()

  assert.equal(mounted.controller.isOpen, false)
  assert.equal(document.activeElement.id, "elsewhere")
})

test("the focus leaving for something else on the page folds the menu", () => {
  openWithFocusOnEntry()

  byId("elsewhere").focus()

  assert.equal(mounted.controller.isOpen, false)
  assert.equal(document.activeElement.id, "elsewhere")
})

test("the focus moving between the button and an entry keeps the menu open", () => {
  openWithFocusOnEntry()

  byId("more").focus()

  assert.equal(mounted.controller.isOpen, true)
})
