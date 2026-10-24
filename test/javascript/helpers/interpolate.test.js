import { test } from "node:test"
import assert from "node:assert/strict"
import { interpolate } from "../../../app/javascript/helpers/interpolate.js"

test("fills a placeholder", () => {
  assert.equal(interpolate("%{percent}% sent", { percent: 38 }), "38% sent")
})

test("fills every occurrence of a placeholder", () => {
  assert.equal(interpolate("%{name}: %{name} is required", { name: "Title" }), "Title: Title is required")
})

test("fills several placeholders", () => {
  assert.equal(interpolate("%{sent} of %{total}", { sent: "0.9 GB", total: "2.3 GB" }), "0.9 GB of 2.3 GB")
})

test("leaves a placeholder no value is given for", () => {
  assert.equal(interpolate("%{hours} h %{minutes} min", { hours: 1 }), "1 h %{minutes} min")
})

test("takes a value literally, pattern characters included", () => {
  assert.equal(interpolate("Could not send %{reason}", { reason: "$& $1 $$" }), "Could not send $& $1 $$")
})

test("leaves a phrase without placeholders as it is", () => {
  assert.equal(interpolate("Ready", { percent: 100 }), "Ready")
})
