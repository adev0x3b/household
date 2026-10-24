import { test } from "node:test"
import assert from "node:assert/strict"
import { ScrollLock } from "../../../app/javascript/helpers/scroll_lock.js"

function page() {
  return { style: { overflow: "" } }
}

test("holding keeps the page from scrolling, releasing lets it", () => {
  const body = page()
  const lock = new ScrollLock(body)

  lock.hold()
  assert.equal(body.style.overflow, "hidden")

  lock.release()
  assert.equal(body.style.overflow, "")
})

test("the page scrolls again only when the last holder lets go", () => {
  const body = page()
  const drawer = new ScrollLock(body)
  const modal = new ScrollLock(body)

  drawer.hold()
  modal.hold()
  modal.release()
  assert.equal(body.style.overflow, "hidden")

  drawer.release()
  assert.equal(body.style.overflow, "")
})

test("holding or releasing twice counts once", () => {
  const body = page()
  const lock = new ScrollLock(body)

  lock.hold()
  lock.hold()
  lock.release()
  assert.equal(body.style.overflow, "")

  lock.release()
  assert.equal(lock.count, 0)
})

test("a release without a hold changes nothing", () => {
  const body = page()
  const other = new ScrollLock(body)
  other.hold()

  new ScrollLock(body).release()
  assert.equal(body.style.overflow, "hidden")
})
