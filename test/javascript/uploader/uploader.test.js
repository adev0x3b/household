import { test } from "node:test"
import assert from "node:assert/strict"
import { Uploader } from "../../../app/javascript/uploader/uploader.js"
import { ConnectionLost, Aborted } from "../../../app/javascript/uploader/server.js"
import { State } from "../../../app/javascript/uploader/transfer.js"

// A file of a size, sliced into chunks that only know their size.
function file(name, size) {
  return { name, size, lastModified: 1, slice: (start, end) => ({ size: end - start }) }
}

// A server whose chunk answers are scripted: a number is the offset it
// reached, an Error is thrown. It records every call.
function fakeServer({ progress = [], chunks = [] } = {}) {
  return {
    calls: [],
    polls: [...progress],
    answers: [...chunks],
    nextId: 1,
    async create(file) {
      this.calls.push(["create", file.name])
      const id = this.nextId++
      return {
        id,
        offset: 0,
        url: `/files/${id}`,
        chunk_url: `/files/${id}/chunk`,
        progress_url: `/files/${id}/progress`
      }
    },
    async progress(url) {
      this.calls.push(["progress", url])
      return this.polls.shift() ?? null
    },
    async sendChunk({ offset, chunk, signal, onProgress }) {
      this.calls.push(["chunk", offset, chunk.size])
      const answer = this.answers.shift()
      if (answer instanceof Error) throw answer
      if (answer === "hang") {
        return new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(new Aborted()))
        })
      }
      onProgress(offset + chunk.size)
      return answer ?? offset + chunk.size
    },
    async destroy(url) {
      this.calls.push(["destroy", url])
    }
  }
}

function fakeMemory(remembered = {}) {
  return {
    remembered,
    recall(file) {
      return this.remembered[file.name] || null
    },
    remember(file, upload) {
      this.remembered[file.name] = upload
    },
    forget(file) {
      delete this.remembered[file.name]
    }
  }
}

function listener() {
  return {
    events: [],
    added(transfer) {
      this.events.push(["added", transfer.file.name])
    },
    changed(transfer) {
      this.events.push(["changed", transfer.file.name, transfer.state, transfer.notice?.key])
    },
    progressed(transfer) {
      this.events.push(["progressed", transfer.file.name, transfer.sent])
    },
    listChanged() {
      this.events.push(["listChanged"])
    }
  }
}

function uploader({ server = fakeServer(), memory = fakeMemory(), hidden = () => false, chunkSize = 400 } = {}) {
  const heard = listener()
  const delays = []
  const queue = new Uploader({
    server,
    memory,
    chunkSize,
    listener: heard,
    hidden,
    delay: (ms) => {
      delays.push(ms)
      return new Promise((resolve) => setImmediate(resolve))
    }
  })
  return { queue, server, memory, heard, delays }
}

// Lets the queue's promises run until the condition holds.
async function until(condition) {
  for (let i = 0; i < 200; i++) {
    if (condition()) return
    await new Promise((resolve) => setImmediate(resolve))
  }
  throw new Error("never happened")
}

test("a file goes up in chunks, then is checked until the server says ready", async () => {
  const { queue, server, heard } = uploader({
    server: fakeServer({ progress: [{ status: "processing" }, { status: "ready" }] })
  })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.deepEqual(
    server.calls.filter(([kind]) => kind !== "progress"),
    [
      ["create", "lease.pdf"],
      ["chunk", 0, 400],
      ["chunk", 400, 400],
      ["chunk", 800, 200]
    ]
  )
  assert.equal(server.calls.filter(([kind]) => kind === "progress").length, 2)
  assert.deepEqual(heard.events.slice(0, 2), [
    ["added", "lease.pdf"],
    ["changed", "lease.pdf", State.UPLOADING, undefined]
  ])
  assert.deepEqual(heard.events.at(-1), ["listChanged"])
  assert.equal(transfer.percent, 100)
})

test("the server's chunk size is used when the page names none", async () => {
  const { queue, server } = uploader({ chunkSize: 0, server: fakeServer({ progress: [{ status: "ready" }] }) })
  server.create = async () => ({ id: 1, offset: 0, chunk_size: 500, chunk_url: "/c", progress_url: "/p", url: "/u" })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.deepEqual(
    server.calls.filter(([kind]) => kind === "chunk").map(([, , size]) => size),
    [500, 500]
  )
})

test("a file picked before goes on from where the server has it", async () => {
  const server = fakeServer({ progress: [{ status: "uploading", offset: 600 }, { status: "ready" }] })
  const memory = fakeMemory({
    "lease.pdf": { id: 9, progress_url: "/files/9/progress", chunk_url: "/files/9/chunk", url: "/files/9" }
  })
  const { queue } = uploader({ server, memory })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.deepEqual(
    server.calls.filter(([kind]) => kind !== "progress"),
    [["chunk", 600, 400]]
  )
  assert.equal(memory.recall(file("lease.pdf", 1000)), null)
})

test("a file the server no longer waits for starts again", async () => {
  const server = fakeServer({ progress: [{ status: "ready" }, { status: "ready" }] })
  const memory = fakeMemory({ "lease.pdf": { id: 9, progress_url: "/files/9/progress" } })
  const { queue } = uploader({ server, memory })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.equal(server.calls[1][0], "create")
})

test("the offset the server names on a disagreement is where the file goes on from", async () => {
  const server = fakeServer({ chunks: [400, 300, 700, 1000], progress: [{ status: "ready" }] })
  const { queue } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.deepEqual(
    server.calls.filter(([kind]) => kind === "chunk").map(([, offset]) => offset),
    [0, 400, 300, 700]
  )
})

test("a chunk lost to the connection is sent again, waiting longer each time", async () => {
  const server = fakeServer({
    chunks: [new ConnectionLost(), new ConnectionLost(), 400, 800, 1000],
    progress: [{ status: "ready" }]
  })
  const { queue, delays, heard } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.deepEqual(delays.slice(0, 2), [1000, 2000])
  assert.ok(heard.events.some(([, , , notice]) => notice === "retrying"))
  assert.equal(server.calls.filter(([kind]) => kind === "chunk").length, 5)
})

test("a connection lost once too often fails the file, which goes again once the page is seen", async () => {
  const lost = Array.from({ length: 6 }, () => new ConnectionLost())
  const server = fakeServer({ chunks: [...lost, 400, 800, 1000], progress: [{ status: "ready" }] })
  const { queue, delays } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.failed)

  assert.equal(transfer.lostConnection, true)
  assert.equal(transfer.notice, null)
  assert.deepEqual(delays, [1000, 2000, 4000, 8000, 16000])

  queue.wake()
  await until(() => transfer.ready)
})

test("a chunk lost in the background waits for the page to be seen, without counting", async () => {
  const page = { hidden: true }
  const server = fakeServer({ chunks: [new ConnectionLost(), 400, 800, 1000], progress: [{ status: "ready" }] })
  const { queue, delays } = uploader({ server, hidden: () => page.hidden })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.notice?.key === "background")
  assert.equal(transfer.attempts, 0)
  assert.equal(server.calls.filter(([kind]) => kind === "chunk").length, 1)

  page.hidden = false
  queue.wake()
  await until(() => transfer.ready)
  assert.deepEqual(delays, [2000])
})

test("the server's refusal is the reason the file failed", async () => {
  const server = fakeServer({ chunks: [new Error("That piece doesn't fit the file.")] })
  const { queue } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.failed)

  assert.equal(transfer.lostConnection, false)
  assert.deepEqual(transfer.notice, { key: "failed_with", values: { reason: "That piece doesn't fit the file." } })
})

test("a paused file stops where it is and goes on from there when resumed", async () => {
  const server = fakeServer({ chunks: [400, "hang", 800, 1000], progress: [{ status: "ready" }] })
  const { queue } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => server.calls.filter(([kind]) => kind === "chunk").length === 2)

  queue.pause(transfer)
  await until(() => !queue.running)
  assert.equal(transfer.state, State.PAUSED)
  assert.equal(transfer.offset, 400)

  queue.resume(transfer)
  await until(() => transfer.ready)
  assert.deepEqual(
    server.calls.filter(([kind]) => kind === "chunk").map(([, offset]) => offset),
    [0, 400, 400, 800]
  )
})

test("a cancelled file is taken off the server and out of the memory", async () => {
  const server = fakeServer({ chunks: ["hang"] })
  const memory = fakeMemory()
  const { queue, heard } = uploader({ server, memory })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => server.calls.some(([kind]) => kind === "chunk"))

  await queue.cancel(transfer)
  assert.equal(transfer.state, State.CANCELLED)
  assert.deepEqual(server.calls.at(-1), ["destroy", "/files/1"])
  assert.equal(memory.recall(file("lease.pdf", 1000)), null)
  assert.deepEqual(heard.events.at(-1), ["listChanged"])
})

test("a file the server found short is sent the rest of", async () => {
  const server = fakeServer({ progress: [{ status: "uploading", offset: 800 }, { status: "ready" }] })
  const { queue } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)

  assert.deepEqual(
    server.calls.filter(([kind]) => kind === "chunk").map(([, offset]) => offset),
    [0, 400, 800, 800]
  )
})

test("a file the server gave up on while checking is lost, and goes up anew when resumed", async () => {
  const server = fakeServer({ progress: [{ status: "processing" }, null, { status: "ready" }] })
  const { queue, heard } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.failed)

  assert.deepEqual(transfer.notice, { key: "gone", values: {} })
  assert.equal(transfer.upload, null)
  assert.deepEqual(heard.events.at(-1), ["listChanged"])

  queue.resume(transfer)
  await until(() => transfer.ready)
  assert.deepEqual(
    server.calls.filter(([kind]) => kind === "create" || kind === "chunk").map(([kind, a]) => `${kind}:${a}`),
    ["create:lease.pdf", "chunk:0", "chunk:400", "chunk:800", "create:lease.pdf", "chunk:0", "chunk:400", "chunk:800"]
  )
})

test("a poll that fails is made again", async () => {
  const server = fakeServer({ progress: [{ status: "ready" }] })
  let failures = 2
  const progress = server.progress.bind(server)
  server.progress = async (url) => {
    if (failures-- > 0) throw new ConnectionLost()
    return progress(url)
  }
  const { queue } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => transfer.ready)
})

test("files go up one at a time, the next while the previous is being checked", async () => {
  const server = fakeServer({
    progress: [{ status: "processing" }, { status: "processing" }, { status: "ready" }, { status: "ready" }]
  })
  const { queue } = uploader({ server })

  const first = queue.add(file("lease.pdf", 500))
  const second = queue.add(file("photo.jpg", 500))
  await until(() => first.ready && second.ready)

  const order = server.calls
    .filter(([kind]) => kind === "create" || kind === "chunk")
    .map(([kind, a]) => `${kind}:${a}`)
  assert.deepEqual(order, ["create:lease.pdf", "chunk:0", "chunk:400", "create:photo.jpg", "chunk:0", "chunk:400"])
  assert.equal(queue.active, false)
})

test("stopping aborts what is on its way and ends the checks", async () => {
  const server = fakeServer({ chunks: ["hang"] })
  const { queue } = uploader({ server })

  const transfer = queue.add(file("lease.pdf", 1000))
  await until(() => server.calls.some(([kind]) => kind === "chunk"))

  queue.stop()
  await until(() => !queue.running)
  assert.equal(transfer.uploading, true)
  assert.equal(queue.stopped, true)
})
