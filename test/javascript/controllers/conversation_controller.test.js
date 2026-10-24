import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount, settle } from "../support/stimulus.js"
import ConversationController from "../../../app/javascript/controllers/conversation_controller.js"

// jsdom lays nothing out. Here every message is 100px tall and the thread's
// box shows six of them, so how far the reader has scrolled can be measured.
const MESSAGE = 100
const BOX = 600
const scrolled = new WeakMap()
Object.defineProperties(window.HTMLElement.prototype, {
  scrollHeight: {
    configurable: true,
    get() {
      return this.querySelectorAll(".message").length * MESSAGE
    }
  },
  clientHeight: { configurable: true, value: BOX },
  scrollTop: {
    configurable: true,
    get() {
      return scrolled.get(this) ?? 0
    },
    set(value) {
      scrolled.set(this, Math.max(0, Math.min(value, this.scrollHeight - this.clientHeight)))
    }
  }
})

// jsdom keeps a file input's files to itself and has no DataTransfer, the
// browser's way of building a list of them; these stand in for both.
class FakeDataTransfer {
  #files = []
  items = { add: (file) => this.#files.push(file), length: 0 }

  constructor() {
    Object.defineProperty(this.items, "length", { get: () => this.#files.length })
  }

  get files() {
    return this.#files
  }
}

function pickable(input) {
  let files = []
  Object.defineProperties(input, {
    files: {
      get: () => files,
      set: (list) => {
        files = list
      }
    },
    value: {
      get: () => (files.length > 0 ? files[0].name : ""),
      set: (value) => {
        if (value === "") files = []
      }
    }
  })
}

const picture = (name, type = "image/jpeg") => ({ name, type })

// A message as Views::Conversations::Bubble draws it.
const message = (id, { mine = false } = {}) =>
  `<article class="message" data-message-id="${id}" data-mine="${mine}"><p>Message ${id}</p></article>`

// A conversation's page as Views::Conversations::Show draws it, with the
// composer's pictures where the household allows them.
function page({ messages = [], pictures = true } = {}) {
  return `
    <div data-controller="conversation" data-conversation-read-url-value="/conversations/1/read_receipt">
      <div data-conversation-target="scroll">
        <div data-conversation-target="thread">${messages.join("")}</div>
      </div>
      <form data-conversation-target="form" data-action="submit->conversation#submit turbo:submit-end->conversation#sent">
        <input type="hidden" name="client_id" data-conversation-target="clientId">
        <div data-conversation-target="preview" hidden>
          <div data-conversation-target="previewImages"></div>
          <template data-conversation-target="previewTemplate">
            <div><img alt=""><button type="button" data-action="click->conversation#removePicture">×</button></div>
          </template>
        </div>
        ${pictures ? pictureInputs() : ""}
        <textarea name="body" data-conversation-target="body"></textarea>
      </form>
    </div>
  `
}

function pictureInputs() {
  return `
    <input type="file" name="images[]" multiple hidden data-conversation-target="files" data-max-files="3">
    <input type="file" accept="image/*" hidden data-conversation-target="camera" data-action="change->conversation#addPictures">
    <input type="file" multiple hidden data-conversation-target="library" data-action="change->conversation#addPictures">
  `
}

let mounted, reads, answer, revoked
const originals = {
  fetch: globalThis.fetch,
  createObjectURL: URL.createObjectURL,
  revokeObjectURL: URL.revokeObjectURL
}

beforeEach(() => {
  document.head.innerHTML = '<meta name="csrf-token" content="token">'
  reads = []
  answer = () => ({ status: 204 })
  globalThis.fetch = async (url, options) => {
    reads.push({ url, ...options, body: JSON.parse(options.body) })
    return answer()
  }
  revoked = []
  URL.createObjectURL = (file) => `blob:${file.name}`
  URL.revokeObjectURL = (url) => revoked.push(url)
  globalThis.DataTransfer = FakeDataTransfer
})

afterEach(() => {
  mounted.stop()
  globalThis.fetch = originals.fetch
  URL.createObjectURL = originals.createObjectURL
  URL.revokeObjectURL = originals.revokeObjectURL
  delete globalThis.DataTransfer
  delete document.visibilityState
})

async function open(options) {
  const html = page(options)
  mounted = await mount("conversation", ConversationController, html)
  if (options?.pictures !== false) {
    for (const input of document.querySelectorAll('input[type="file"]')) pickable(input)
  }
  await settle()
  return mounted
}

const box = () => document.querySelector('[data-conversation-target="scroll"]')
const thread = () => document.querySelector('[data-conversation-target="thread"]')
const field = (target) => document.querySelector(`[data-conversation-target="${target}"]`)
const atBottom = () => box().scrollTop === box().scrollHeight - box().clientHeight
const sentIds = () => reads.map((read) => read.body.message_id)

function hide() {
  Object.defineProperty(document, "visibilityState", { configurable: true, value: "hidden" })
  document.dispatchEvent(new Event("visibilitychange"))
}

function show() {
  delete document.visibilityState
  document.dispatchEvent(new Event("visibilitychange"))
}

async function arrive(html) {
  thread().insertAdjacentHTML("beforeend", html)
  await settle()
}

function pick(input, files) {
  input.files = files
  input.dispatchEvent(new Event("change", { bubbles: true }))
}

function submit() {
  const event = new Event("submit", { bubbles: true, cancelable: true })
  field("form").dispatchEvent(event)
  return event
}

const sendEnded = (success) =>
  field("form").dispatchEvent(new CustomEvent("turbo:submit-end", { bubbles: true, detail: { success } }))

const thread12 = () => Array.from({ length: 12 }, (_, index) => message(index + 1, { mine: index % 2 === 0 }))

test("the thread opens at the newest message", async () => {
  await open({ messages: thread12() })

  assert.ok(atBottom())
})

test("a message from someone else follows a reader at the end of the thread", async () => {
  await open({ messages: thread12() })

  await arrive(message(13))

  assert.ok(atBottom())
})

test("a message from someone else leaves a reader who scrolled up where they are", async () => {
  await open({ messages: thread12() })
  box().scrollTop = 100

  await arrive(message(13))

  assert.equal(box().scrollTop, 100)
})

test("the reader's own message takes them to the end, wherever they were", async () => {
  await open({ messages: thread12() })
  box().scrollTop = 100

  await arrive(message(13, { mine: true }))

  assert.ok(atBottom())
})

test("earlier messages put above keep the reader on the message they were reading", async () => {
  await open({ messages: thread12() })
  box().scrollTop = 0
  mounted.controller.loadingOlder()

  thread().insertAdjacentHTML("afterbegin", message(-2) + message(-1))
  await settle()

  assert.equal(box().scrollTop, 2 * MESSAGE)
})

test("once earlier messages are in, a new message is followed and read again", async () => {
  await open({ messages: thread12() })
  mounted.controller.loadingOlder()
  thread().insertAdjacentHTML("afterbegin", message(-1))
  await settle()
  box().scrollTop = box().scrollHeight

  await arrive(message(13))

  assert.ok(atBottom())
  assert.deepEqual(sentIds(), [12, 13])
})

test("opening the thread tells the server the newest message from someone else was read", async () => {
  await open({ messages: [message(1), message(2), message(3, { mine: true })] })

  assert.deepEqual(sentIds(), [2])
  assert.equal(reads[0].url, "/conversations/1/read_receipt")
  assert.equal(reads[0].method, "POST")
  assert.equal(reads[0].headers["X-CSRF-Token"], "token")
  assert.equal(reads[0].keepalive, true)
})

test("a thread of the reader's own messages reads nothing", async () => {
  await open({ messages: [message(1, { mine: true })] })

  assert.deepEqual(reads, [])
})

test("a message that arrives is read at once", async () => {
  await open({ messages: [message(1)] })

  await arrive(message(2))

  assert.deepEqual(sentIds(), [1, 2])
})

test("a message that arrives in a tab out of sight is read when the tab comes to the front", async () => {
  await open({ messages: [message(1)] })
  hide()

  await arrive(message(2))
  await arrive(message(3))
  assert.deepEqual(sentIds(), [1])

  show()
  assert.deepEqual(sentIds(), [1, 3])
})

test("a read the server couldn't save is sent again with the next one", async () => {
  answer = () => ({ status: 503 })
  await open({ messages: [message(4)] })
  await settle()

  answer = () => ({ status: 204 })
  hide()
  show()

  assert.deepEqual(sentIds(), [4, 4])
})

test("a read lost with the connection is sent again", async () => {
  answer = () => {
    throw new TypeError("Failed to fetch")
  }
  await open({ messages: [message(4)] })
  await settle()

  answer = () => ({ status: 204 })
  await arrive(message(5, { mine: true }))
  hide()
  show()

  assert.deepEqual(sentIds(), [4, 4])
})

test("a read the server refused is not asked again", async () => {
  answer = () => ({ status: 404 })
  await open({ messages: [message(4)] })
  await settle()

  hide()
  show()

  assert.deepEqual(sentIds(), [4])
})

test("each page gets a client id, and each send a fresh one", async () => {
  await open()
  const first = field("clientId").value

  sendEnded(true)

  assert.match(first, /^[0-9a-f-]{36}$/)
  assert.notEqual(field("clientId").value, first)
})

test("a send with neither words nor pictures is stopped", async () => {
  await open()

  field("body").value = "   "

  assert.equal(submit().defaultPrevented, true)
})

test("a send with words goes", async () => {
  await open()

  field("body").value = "On my way"

  assert.equal(submit().defaultPrevented, false)
})

test("a send with only a picture goes", async () => {
  await open()

  pick(field("library"), [picture("a.jpg")])

  assert.equal(submit().defaultPrevented, false)
})

test("a household without pictures still sends words", async () => {
  await open({ pictures: false })

  field("body").value = "On my way"
  assert.equal(submit().defaultPrevented, false)

  sendEnded(true)
  assert.equal(field("body").value, "")
})

test("pictures picked join those waiting, up to the most a message takes, and only pictures", async () => {
  await open()

  pick(field("camera"), [picture("shot.jpg")])
  pick(field("library"), [picture("a.png", "image/png"), picture("notes.pdf", "application/pdf"), picture("b.jpg")])
  pick(field("library"), [picture("c.jpg")])

  assert.deepEqual(
    field("files").files.map((file) => file.name),
    ["shot.jpg", "a.png", "b.jpg"]
  )
})

test("the input a picture came from is emptied, so the same one can be picked again", async () => {
  await open()

  pick(field("library"), [picture("a.jpg")])

  assert.deepEqual(field("library").files, [])
})

test("each picture waiting is shown, and removing one sends the others", async () => {
  await open()
  pick(field("library"), [picture("a.jpg"), picture("b.jpg")])
  await settle()

  const thumbnails = () => Array.from(field("previewImages").querySelectorAll("img")).map((image) => image.src)
  assert.equal(field("preview").hidden, false)
  assert.deepEqual(thumbnails(), ["blob:a.jpg", "blob:b.jpg"])

  field("previewImages").querySelectorAll("button")[0].click()
  assert.deepEqual(
    field("files").files.map((file) => file.name),
    ["b.jpg"]
  )
  assert.deepEqual(thumbnails(), ["blob:b.jpg"])
  assert.ok(revoked.includes("blob:a.jpg"))

  await settle()
  field("previewImages").querySelector("button").click()
  assert.equal(field("preview").hidden, true)
})

test("a message sent empties the box and the pictures, and leaves the cursor in the box", async () => {
  await open()
  field("body").value = "Look"
  pick(field("library"), [picture("a.jpg")])

  sendEnded(true)

  assert.equal(field("body").value, "")
  assert.deepEqual(field("files").files, [])
  assert.equal(field("preview").hidden, true)
  assert.equal(field("previewImages").children.length, 0)
  assert.deepEqual(revoked, ["blob:a.jpg"])
  assert.equal(document.activeElement, field("body"))
})

test("a send that failed keeps the words, the pictures and the client id", async () => {
  await open()
  const clientId = field("clientId").value
  field("body").value = "Look"
  pick(field("library"), [picture("a.jpg")])

  sendEnded(false)

  assert.equal(field("body").value, "Look")
  assert.equal(field("files").files.length, 1)
  assert.equal(field("clientId").value, clientId)
})
