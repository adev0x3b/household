import { test } from "node:test"
import assert from "node:assert/strict"
import { Wording } from "../../../app/javascript/uploader/wording.js"
import { Transfer } from "../../../app/javascript/uploader/transfer.js"

const words = {
  queued: "Waiting",
  uploading: "Uploading…",
  ready: "Done",
  retrying: "Connection lost, retrying…",
  failed_with: "Failed: %{reason}",
  progress: "%{percent}% · %{sent} of %{total}",
  speed: "%{speed}/s",
  eta_seconds: "%{count} s left",
  eta_minutes: "%{count} min left",
  eta_hours: "%{hours} h %{minutes} min left",
  row: "Uploading, %{percent}%"
}

const wording = new Wording(words, "en")
const file = { name: "lease.pdf", size: 2 * 1024 * 1024 * 1024 }

test("a state is worded, and a key with no word stays as it is", () => {
  const transfer = new Transfer(file)

  assert.equal(wording.status(transfer), "Waiting")
  assert.equal(wording.word("unknown"), "unknown")
})

test("a notice is worded in place of the state", () => {
  const transfer = new Transfer(file)
  transfer.start()
  transfer.retry()
  assert.equal(wording.status(transfer), "Connection lost, retrying…")

  transfer.fail("too big")
  assert.equal(wording.status(transfer), "Failed: too big")
})

test("sizes are written in powers of 1024, with one decimal under ten", () => {
  assert.equal(wording.size(0), "0 B")
  assert.equal(wording.size(1023), "1,023 B")
  assert.equal(wording.size(1536), "1.5 KB")
  assert.equal(wording.size(15 * 1024), "15 KB")
  assert.equal(wording.size(2.3 * 1024 ** 3), "2.3 GB")
})

test("sizes follow the page's language", () => {
  assert.equal(new Wording(words, "it").size(1536), "1,5 KB")
})

test("a file not started shows its size alone", () => {
  assert.equal(wording.figures(new Transfer(file)), "2.0 GB")
})

test("a file going up shows how far, how fast and how long", () => {
  const transfer = new Transfer(file)
  transfer.start()
  transfer.speedometer = { bytesPerSecond: 8.4 * 1024 * 1024, reset() {}, record() {} }
  transfer.progress(0.9 * 1024 ** 3)

  assert.equal(wording.figures(transfer), "45% · 922 MB of 2.0 GB · 8.4 MB/s · 3 min left")
})

test("a file going up at no measured speed shows how far alone", () => {
  const transfer = new Transfer(file)
  transfer.start()
  transfer.progress(1024 ** 3)

  assert.equal(wording.figures(transfer), "50% · 1.0 GB of 2.0 GB")
})

test("the time left is worded in seconds, minutes or hours", () => {
  assert.equal(wording.timeLeft(0.2), "1 s left")
  assert.equal(wording.timeLeft(59), "59 s left")
  assert.equal(wording.timeLeft(61), "2 min left")
  assert.equal(wording.timeLeft(3600 * 2 + 60 * 5), "2 h 5 min left")
  assert.equal(wording.timeLeft(Infinity), "")
})

test("the row behind says the percentage", () => {
  assert.equal(wording.rowStatus(38), "Uploading, 38%")
})
