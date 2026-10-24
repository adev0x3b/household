import { test, beforeEach, afterEach, mock } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import ToastController from "../../../app/javascript/controllers/toast_controller.js"

// A toast as Components::Toast draws it: a success, which goes by itself,
// or an alert, which stays until it is closed.
const toast = (untilClosed) => `
  <div class="toast" data-controller="toast" data-toast-until-closed-value="${untilClosed}"
       data-action="mouseenter->toast#pauseTimer mouseleave->toast#resumeTimer focusin->toast#pauseTimer focusout->toast#resumeTimer">
    <span class="toast__message">Saved</span>
    <button type="button" class="toast__close">Close</button>
    <progress data-toast-target="progress" max="100" value="100"></progress>
  </div>
  <button type="button" id="elsewhere">Elsewhere</button>
`

let mounted

// The clock is the test's, so a toast's time passes only when it says.
beforeEach(() => mock.timers.enable({ apis: ["setTimeout", "Date"] }))

afterEach(() => {
  mounted?.stop()
  mock.timers.reset()
})

const closing = () => mounted.element.classList.contains("is-removing")

test("a toast goes by itself after its duration", async () => {
  mounted = await mount("toast", ToastController, toast(false))

  mock.timers.tick(4999)
  assert.equal(closing(), false)
  mock.timers.tick(1)
  assert.equal(closing(), true)
})

test("an alert stays until it is closed", async () => {
  mounted = await mount("toast", ToastController, toast(true))

  mock.timers.tick(60_000)
  assert.equal(closing(), false)

  mounted.controller.close()
  assert.equal(closing(), true)
})

test("it waits while the focus is in it, and goes on from where it was once the focus leaves", async () => {
  mounted = await mount("toast", ToastController, toast(false))
  const close = mounted.element.querySelector(".toast__close")

  mock.timers.tick(3000)
  close.focus()
  mock.timers.tick(60_000)
  assert.equal(closing(), false)

  document.getElementById("elsewhere").focus()
  mock.timers.tick(1999)
  assert.equal(closing(), false)
  mock.timers.tick(1)
  assert.equal(closing(), true)
})

test("the pointer leaving does not start it again while the focus is still in it", async () => {
  mounted = await mount("toast", ToastController, toast(false))

  mounted.element.dispatchEvent(new MouseEvent("mouseenter"))
  mounted.element.querySelector(".toast__close").focus()
  mounted.element.dispatchEvent(new MouseEvent("mouseleave"))
  mock.timers.tick(60_000)

  assert.equal(closing(), false)
})
