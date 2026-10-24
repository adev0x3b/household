import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "helpers/csrf"
import { Composer } from "helpers/composer"

// A reader this close (px) to the end of the thread is following it, and
// is taken along when a message arrives.
const FOLLOWING = 160

// A conversation's page (Views::Conversations::Show). The thread keeps the
// reader at the newest message when they are near the end or the message
// is their own, and keeps their place when earlier messages are put above.
// It tells the server what the reader has seen, so the sender sees "Seen"
// and the bell stays quiet. The composer sends with Enter, mints a fresh
// client id after every send, and collects pictures from the camera or the
// library into the one input the form sends, previewed as they come.
export default class extends Controller {
  static targets = [
    "scroll",
    "thread",
    "form",
    "body",
    "clientId",
    "files",
    "camera",
    "library",
    "preview",
    "previewImages",
    "previewTemplate"
  ]
  static values = { readUrl: String }

  connect() {
    this.mintClientId()
    this.pendingRead = null
    this.observer = new MutationObserver((records) => this.changed(records))
    this.observer.observe(this.scrollTarget, { childList: true, subtree: true })
    document.addEventListener("visibilitychange", this.#flushReadWhenVisible)
    this.queueRead(this.scrollTarget.querySelectorAll(".message"))
    this.scrollToBottom()
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("visibilitychange", this.#flushReadWhenVisible)
  }

  // Listened for on the document, which is why it is kept as a field:
  // removing a listener needs the same function.
  #flushReadWhenVisible = () => {
    if (document.visibilityState === "visible") this.flushRead()
  }

  changed(records) {
    const added = records
      .flatMap((record) => Array.from(record.addedNodes))
      .filter((node) => node.nodeType === Node.ELEMENT_NODE && node.matches(".message"))
    if (added.length === 0) return

    if (this.olderHeight !== undefined) {
      // Earlier messages went above: stay on the one that was at the top.
      this.scrollTarget.scrollTop += this.scrollTarget.scrollHeight - this.olderHeight
      this.olderHeight = undefined
      return
    }

    const mine = added.some((node) => node.dataset.mine === "true")
    if (mine || this.nearBottom) this.scrollToBottom()

    this.queueRead(added)
  }

  // Opening the page reads nothing by itself, since Turbo prefetches a
  // hovered link: a message counts as read once the page is seen, which
  // for a page in a background tab is when it comes to the front.
  queueRead(messages) {
    const theirs = Array.from(messages)
      .filter((node) => node.dataset.mine !== "true")
      .map((node) => Number(node.dataset.messageId))
    if (theirs.length === 0) return

    this.pendingRead = Math.max(this.pendingRead || 0, ...theirs)
    if (document.visibilityState === "visible") this.flushRead()
  }

  loadingOlder() {
    this.olderHeight = this.scrollTarget.scrollHeight
  }

  get nearBottom() {
    const box = this.scrollTarget
    return box.scrollHeight - box.scrollTop - box.clientHeight < FOLLOWING
  }

  scrollToBottom() {
    this.scrollTarget.scrollTop = this.scrollTarget.scrollHeight
  }

  // Sent with keepalive, so a read still lands when the reader goes back or
  // closes the app at once. A read the server couldn't save waits for the
  // next one, or for the page to come to the front again; one it refused
  // (signed out, a message that is gone) is not asked again.
  flushRead() {
    if (!this.pendingRead) return

    const id = this.pendingRead
    this.pendingRead = null
    fetch(this.readUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken(), "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ message_id: id }),
      credentials: "same-origin",
      keepalive: true
    })
      .then((response) => {
        if (response.status >= 500) this.#readLater(id)
      })
      .catch(() => this.#readLater(id))
  }

  #readLater(id) {
    this.pendingRead = Math.max(this.pendingRead || 0, id)
  }

  // A send repeated by a bad connection carries the same id, and is saved once.
  mintClientId() {
    this.clientIdTarget.value = crypto.randomUUID()
  }

  // Pictures are a household setting, so the files input may not be there.
  submit(event) {
    const hasText = this.bodyTarget.value.trim() !== ""
    const hasFiles = this.hasFilesTarget && this.filesTarget.files.length > 0
    if (!hasText && !hasFiles) event.preventDefault()
  }

  sent(event) {
    if (!event.detail.success) return

    this.composer.clear()
    this.clearFiles()
    this.mintClientId()
    this.bodyTarget.focus()
  }

  keydown(event) {
    this.composer.keydown(event)
  }

  grow() {
    this.composer.grow()
  }

  get composer() {
    return new Composer(this.formTarget, this.bodyTarget)
  }

  openCamera() {
    this.cameraTarget.click()
  }

  openLibrary() {
    this.libraryTarget.click()
  }

  // What the camera or the library gave joins what is already waiting, up
  // to max-files (the server takes no more), and that input is emptied so
  // the same shot can be taken again. Nothing goes up before the send.
  addPictures(event) {
    const source = event.target
    const max = Number(this.filesTarget.dataset.maxFiles) || 1
    const kept = new DataTransfer()
    Array.from(this.filesTarget.files).forEach((file) => kept.items.add(file))
    Array.from(source.files).forEach((file) => {
      if (kept.items.length < max && file.type.startsWith("image/")) kept.items.add(file)
    })
    this.filesTarget.files = kept.files
    source.value = ""
    this.renderPreview()
  }

  removePicture(event) {
    const index = Number(event.currentTarget.dataset.index)
    const kept = new DataTransfer()
    Array.from(this.filesTarget.files).forEach((file, i) => {
      if (i !== index) kept.items.add(file)
    })
    this.filesTarget.files = kept.files
    this.renderPreview()
  }

  // One thumbnail per picture, from the composer's template: only the
  // picture and which one it is are filled in.
  renderPreview() {
    this.clearThumbnails()
    Array.from(this.filesTarget.files).forEach((file, index) => {
      const item = this.previewTemplateTarget.content.firstElementChild.cloneNode(true)
      item.querySelector("img").src = URL.createObjectURL(file)
      item.querySelector("button").dataset.index = index
      this.previewImagesTarget.appendChild(item)
    })
    this.previewTarget.hidden = this.filesTarget.files.length === 0
  }

  clearFiles() {
    if (!this.hasFilesTarget) return

    this.filesTarget.value = ""
    this.previewTarget.hidden = true
    this.clearThumbnails()
  }

  clearThumbnails() {
    this.previewImagesTarget.querySelectorAll("img").forEach((image) => URL.revokeObjectURL(image.src))
    this.previewImagesTarget.replaceChildren()
  }
}
