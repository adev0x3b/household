import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { Server, ConnectionLost } from "../../../app/javascript/uploader/server.js"

// The browser's side, as much of it as the server's requests use: a page
// with no CSRF meta tag, an XMLHttpRequest that answers as scripted, and a
// fetch that answers as scripted.
const browser = {}
let answer

beforeEach(() => {
  Object.assign(browser, {
    document: globalThis.document,
    XMLHttpRequest: globalThis.XMLHttpRequest,
    fetch: globalThis.fetch
  })
  globalThis.document = { querySelector: () => null }
  globalThis.XMLHttpRequest = FakeRequest
  globalThis.fetch = async () => {
    if (answer instanceof Error) throw answer

    return { status: answer.status, ok: answer.status < 300, json: async () => answer.body }
  }
})

afterEach(() => Object.assign(globalThis, browser))

class FakeRequest {
  constructor() {
    this.upload = {}
  }

  open() {}

  setRequestHeader() {}

  getResponseHeader(name) {
    return answer.headers?.[name] ?? null
  }

  abort() {}

  send() {
    if (answer.lost) return this.onerror()

    this.status = answer.status
    this.responseText = answer.body === undefined ? "<html>Bad gateway</html>" : JSON.stringify(answer.body)
    this.onload()
  }
}

function sendChunk(offset = 0) {
  return new Server("/files").sendChunk({
    url: "/files/1/chunks",
    offset,
    chunk: { size: 400 },
    signal: new EventTarget(),
    onProgress: () => {}
  })
}

test("a chunk appended resolves with where the file has got to", async () => {
  answer = { status: 204, headers: { "Upload-Offset": "400" } }

  assert.equal(await sendChunk(), 400)
})

test("a last chunk sent again after its answer was lost finds the file whole", async () => {
  for (const status of ["processing", "ready"]) {
    answer = { status: 422, headers: { "Upload-Offset": "1000" }, body: { offset: 1000, status } }

    assert.equal(await sendChunk(600), 1000)
  }
})

test("an app restarting behind its proxy is a connection lost, to be tried again", async () => {
  for (const status of [502, 503, 504]) {
    answer = { status }

    await assert.rejects(sendChunk(), ConnectionLost)
  }
})

test("any other refusal fails with the app's reason, else the status", async () => {
  answer = { status: 422, body: { error: "Invalid authenticity token" } }
  await assert.rejects(sendChunk(), { message: "Invalid authenticity token" })

  answer = { status: 413 }
  await assert.rejects(sendChunk(), { message: "413" })
})

test("an upload's progress, null once the server no longer has it", async () => {
  answer = { status: 200, body: { status: "processing", offset: 1000 } }
  assert.deepEqual(await new Server("/files").progress("/files/1/progress"), { status: "processing", offset: 1000 })

  answer = { status: 404, body: {} }
  assert.equal(await new Server("/files").progress("/files/1/progress"), null)
})

test("a progress that can't be had is a connection lost, or the status", async () => {
  answer = new TypeError("Failed to fetch")
  await assert.rejects(new Server("/files").progress("/files/1/progress"), ConnectionLost)

  answer = { status: 503 }
  await assert.rejects(new Server("/files").progress("/files/1/progress"), ConnectionLost)

  answer = { status: 500 }
  await assert.rejects(new Server("/files").progress("/files/1/progress"), { message: "500" })
})
