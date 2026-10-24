import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import ReactionPickerController from "../../../app/javascript/controllers/reaction_picker_controller.js"

// Two messages' smiles and the page's one picker, as
// Views::Conversations::Show draws them: Sam's message on the left, and the
// viewer's own on the right.
const PAGE = `
  <div data-controller="reaction-picker">
    <div id="message_1" class="message message--theirs">
      Bins go out tonight
      <button id="theirs" aria-expanded="false" data-action="reaction-picker#open"
              data-reaction-picker-url-param="/messages/1/reaction" data-reaction-picker-message-param="message_1"
              data-reaction-picker-align-param="start">React</button>
    </div>
    <div id="message_2" class="message message--mine">
      On it
      <button id="mine" aria-expanded="false" data-action="reaction-picker#open"
              data-reaction-picker-url-param="/messages/2/reaction" data-reaction-picker-message-param="message_2"
              data-reaction-picker-align-param="end">React</button>
    </div>
    <div id="reaction_picker" role="group" data-reaction-picker-target="menu"
         data-action="turbo:before-morph-element->reaction-picker#holdWhileOpen">
      <form method="post" data-reaction-picker-target="form" data-action="submit->reaction-picker#chosen">
        <button type="submit" name="emoji" value="👍">👍</button>
        <button type="submit" name="emoji" value="❤️">❤️</button>
      </form>
    </div>
  </div>
`

// Where things sit on a phone's screen: jsdom lays nothing out.
const BOXES = {
  message_1: { top: 300, bottom: 360, left: 16, right: 260 },
  theirs: { top: 330, bottom: 350, left: 268, right: 288 },
  message_2: { top: 400, bottom: 440, left: 150, right: 374 },
  mine: { top: 410, bottom: 430, left: 122, right: 142 },
  reaction_picker: { top: 0, bottom: 48, left: 0, right: 200 }
}

let page
beforeEach(async () => {
  page = await mount("reaction-picker", ReactionPickerController, PAGE)
  for (const [id, box] of Object.entries(BOXES)) {
    document.getElementById(id).getBoundingClientRect = () => ({
      ...box,
      width: box.right - box.left,
      height: box.bottom - box.top
    })
  }
  Object.defineProperty(document.documentElement, "clientWidth", { value: 390, configurable: true })
  document.elementFromPoint = () => picker()
})
afterEach(() => page.stop())

const picker = () => document.getElementById("reaction_picker")
const press = (id) => document.getElementById(id).click()
const shown = () => picker().classList.contains("is-open")
const placed = () => [picker().style.top, picker().style.left]

test("a message's smile opens the picker sending to that message, focus on its first emoji", () => {
  press("theirs")

  assert.equal(shown(), true)
  assert.equal(picker().querySelector("form").getAttribute("action"), "/messages/1/reaction")
  assert.equal(document.getElementById("theirs").getAttribute("aria-expanded"), "true")
  assert.equal(document.activeElement, picker().querySelector("button"))
})

test("it opens over the message, from its left edge for someone else's", () => {
  press("theirs")

  assert.deepEqual(placed(), ["248px", "16px"])
})

test("and from its right edge for the viewer's own", () => {
  press("mine")

  assert.deepEqual(placed(), ["348px", "174px"])
  assert.equal(picker().querySelector("form").getAttribute("action"), "/messages/2/reaction")
})

test("a second press on the same smile closes it, and Escape closes it with focus back on the smile", () => {
  press("theirs")
  press("theirs")
  assert.equal(shown(), false)

  press("theirs")
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
  assert.equal(shown(), false)
  assert.equal(document.activeElement, document.getElementById("theirs"))
})

test("an emoji chosen folds the picker, with focus back on the smile", () => {
  press("mine")
  picker()
    .querySelector("form")
    .dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

  assert.equal(shown(), false)
  assert.equal(document.activeElement, document.getElementById("mine"))
})

test("a page refresh leaves the picker as it is while open, and morphs it once closed", () => {
  const morph = () => {
    const event = new CustomEvent("turbo:before-morph-element", { bubbles: true, cancelable: true })
    picker().dispatchEvent(event)
    return event.defaultPrevented
  }

  press("theirs")
  assert.equal(morph(), true)
  press("theirs")
  assert.equal(morph(), false)
})
