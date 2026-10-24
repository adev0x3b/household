import "../support/dom.js"
import { test } from "node:test"
import assert from "node:assert/strict"
import { Row } from "../../../app/javascript/uploader/row.js"

// The view's template for a file's row, as much of it as the row reads.
function template() {
  const node = document.createElement("template")
  node.innerHTML = `
    <li data-state="queued">
      <span data-role="name"></span>
      <span role="status" data-role="status"></span>
      <div role="progressbar" data-role="bar"></div>
      <span data-role="stats"></span>
    </li>`
  return node
}

test("a file's row shows its name, and names its progress bar after it for a screen reader", () => {
  const row = Row.from(template(), { name: "lease.pdf" }, null)

  assert.equal(row.node.querySelector("[data-role=name]").textContent, "lease.pdf")
  assert.equal(row.node.querySelector("[role=progressbar]").getAttribute("aria-label"), "lease.pdf")
})
