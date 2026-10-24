import { test } from "node:test"
import assert from "node:assert/strict"
import { Transfer, State } from "../../../app/javascript/uploader/transfer.js"

const file = { name: "lease.pdf", size: 1000, lastModified: 1 }

test("a file starts queued, with nothing sent", () => {
  const transfer = new Transfer(file)

  assert.equal(transfer.state, State.QUEUED)
  assert.equal(transfer.active, true)
  assert.equal(transfer.settled, true)
  assert.equal(transfer.percent, 0)
})

test("an empty file is whole from the start", () => {
  const transfer = new Transfer({ ...file, size: 0 })

  assert.equal(transfer.percent, 100)
  assert.equal(transfer.finished, true)
})

test("goes on from the offset the server has", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.startFrom({ id: 7, offset: 400 })
  transfer.progress(transfer.offset)
  assert.equal(transfer.uploading, true)
  assert.equal(transfer.percent, 40)
  assert.equal(transfer.finished, false)
})

test("advancing past the end finishes the sending", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.startFrom({ id: 7, offset: 0 })
  transfer.advance(1000)
  assert.equal(transfer.finished, true)
  assert.equal(transfer.percent, 100)
})

test("a retry is counted and said, and an advance clears the count", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.retry()
  transfer.retry()
  assert.equal(transfer.attempts, 2)
  assert.deepEqual(transfer.notice, { key: "retrying", values: {} })

  transfer.advance(500)
  assert.equal(transfer.attempts, 0)
})

test("a change of state drops the notice", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.waitForTheForeground()
  transfer.pause()
  assert.equal(transfer.notice, null)
  assert.equal(transfer.resumable, true)
  assert.equal(transfer.active, false)
})

test("a failure with the server's reason says it", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.fail("Not enough room")
  assert.equal(transfer.failed, true)
  assert.equal(transfer.lostConnection, false)
  assert.deepEqual(transfer.notice, { key: "failed_with", values: { reason: "Not enough room" } })
})

test("a failure for a lost connection says nothing more, and is tried again on its own", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.retry()
  transfer.fail()
  assert.equal(transfer.lostConnection, true)
  assert.equal(transfer.notice, null)

  transfer.requeue()
  assert.equal(transfer.queued, true)
  assert.equal(transfer.attempts, 0)
  assert.equal(transfer.lostConnection, false)
})

test("a file the server no longer has fails, saying so, and starts over when resumed", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.startFrom({ id: 7, offset: 1000 })
  transfer.advance(1000)
  transfer.finishSending()
  transfer.lose()
  assert.equal(transfer.failed, true)
  assert.equal(transfer.resumable, true)
  assert.equal(transfer.lostConnection, false)
  assert.deepEqual(transfer.notice, { key: "gone", values: {} })
  assert.deepEqual([transfer.upload, transfer.offset, transfer.percent], [null, 0, 0])
})

test("a file sent whole is checked, then ready", () => {
  const transfer = new Transfer(file)

  transfer.start()
  transfer.finishSending()
  assert.equal(transfer.processing, true)
  assert.equal(transfer.settled, true)
  assert.equal(transfer.cancellable, true)

  transfer.finish()
  assert.equal(transfer.ready, true)
  assert.equal(transfer.percent, 100)
  assert.equal(transfer.cancellable, false)
})

test("a cancelled file can't be cancelled again", () => {
  const transfer = new Transfer(file)

  transfer.cancel()
  assert.equal(transfer.cancellable, false)
  assert.equal(transfer.resumable, false)
})
