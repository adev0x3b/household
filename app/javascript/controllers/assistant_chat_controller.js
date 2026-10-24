import { Controller } from "@hotwired/stimulus"
import { Composer } from "helpers/composer"

// The assistant's chat page (Views::Assistant::Chats::Show): the thread
// stays scrolled to the newest message as a reply streams in, the message
// box sends with Enter, and the time zone goes along with a message so
// "today" is the reader's today.
export default class extends Controller {
  static targets = ["thread", "form", "input", "timeZone", "fileInput", "preview", "previewImages", "previewTemplate"]

  connect() {
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.threadTarget, { childList: true, subtree: true, characterData: true })
    this.scrollToBottom()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  submit(event) {
    this.timeZoneTarget.value = Intl.DateTimeFormat().resolvedOptions().timeZone || ""
    const hasText = this.inputTarget.value.trim() !== ""
    const hasFile = this.fileInputTarget.files.length > 0
    if (!hasText && !hasFile) event.preventDefault()
  }

  reset(event) {
    if (event.detail.success) this.composer.clear()
  }

  keydown(event) {
    this.composer.keydown(event)
  }

  grow() {
    this.composer.grow()
  }

  // The server replaces the composer while a reply runs, so it is built
  // from the targets as they are now rather than kept from connect().
  get composer() {
    return new Composer(this.formTarget, this.inputTarget)
  }

  pickFile() {
    this.fileInputTarget.click()
  }

  // Thumbnails of the pictures picked; nothing goes up before the send.
  // Only the first max-files of them are kept, as the server takes no more.
  previewFile() {
    const input = this.fileInputTarget
    const max = Number(input.dataset.maxFiles) || 1
    if (input.files.length > max) {
      const kept = new DataTransfer()
      Array.from(input.files)
        .slice(0, max)
        .forEach((file) => kept.items.add(file))
      input.files = kept.files
    }
    this.clearThumbnails()
    Array.from(input.files).forEach((file) => {
      const image = this.previewTemplateTarget.content.firstElementChild.cloneNode(true)
      image.src = URL.createObjectURL(file)
      this.previewImagesTarget.appendChild(image)
    })
    this.previewTarget.hidden = input.files.length === 0
  }

  clearFile() {
    this.fileInputTarget.value = ""
    this.previewTarget.hidden = true
    this.clearThumbnails()
  }

  clearThumbnails() {
    this.previewImagesTarget.querySelectorAll("img").forEach((image) => URL.revokeObjectURL(image.src))
    this.previewImagesTarget.replaceChildren()
  }

  scrollToBottom() {
    this.threadTarget.scrollTop = this.threadTarget.scrollHeight
  }
}
