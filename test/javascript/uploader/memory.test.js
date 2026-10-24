import { test } from "node:test"
import assert from "node:assert/strict"
import { UnfinishedUploads } from "../../../app/javascript/uploader/memory.js"

const DAY = 24 * 60 * 60 * 1000
const lease = { name: "lease.pdf", size: 2048, lastModified: 1700000000000 }
const photo = { name: "photo.jpg", size: 4096, lastModified: 1700000000000 }

function memory({ broken = false } = {}) {
  const clock = { at: 1000 }
  const store = new Map()
  const storage = {
    getItem: (key) => store.get(key) ?? null,
    setItem(key, value) {
      if (broken) throw new Error("QuotaExceededError")
      store.set(key, value)
    }
  }
  return { clock, store, uploads: new UnfinishedUploads({ storage, now: () => clock.at }) }
}

test("remembers a file's upload and recalls it by name, size and modification time", () => {
  const { uploads } = memory()

  uploads.remember(lease, { id: 7, progress_url: "/files/7/progress" })
  assert.deepEqual(uploads.recall({ ...lease }), { id: 7, progress_url: "/files/7/progress", at: 1000 })
  assert.equal(uploads.recall(photo), null)
})

test("a file edited since is another file", () => {
  const { uploads } = memory()

  uploads.remember(lease, { id: 7 })
  assert.equal(uploads.recall({ ...lease, lastModified: lease.lastModified + 1 }), null)
})

test("forgets a file", () => {
  const { uploads } = memory()

  uploads.remember(lease, { id: 7 })
  uploads.remember(photo, { id: 8 })
  uploads.forget(lease)
  assert.equal(uploads.recall(lease), null)
  assert.equal(uploads.recall(photo).id, 8)
})

test("drops what is older than a day when it writes", () => {
  const { clock, uploads } = memory()

  uploads.remember(lease, { id: 7 })
  clock.at += DAY + 1
  uploads.remember(photo, { id: 8 })
  assert.equal(uploads.recall(lease), null)
  assert.equal(uploads.recall(photo).id, 8)
})

test("remembers nothing when the storage holds something else", () => {
  const { store, uploads } = memory()

  store.set("household:uploads", "not json")
  assert.equal(uploads.recall(lease), null)
})

test("goes on when the storage refuses to write", () => {
  const { uploads } = memory({ broken: true })

  uploads.remember(lease, { id: 7 })
  assert.equal(uploads.recall(lease), null)
})
