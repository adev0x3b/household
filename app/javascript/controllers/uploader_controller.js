import { Controller } from "@hotwired/stimulus"
import { Uploader } from "uploader/uploader"
import { Server } from "uploader/server"
import { UnfinishedUploads } from "uploader/memory"
import { Wording } from "uploader/wording"
import { Row } from "uploader/row"
import { Screen } from "uploader/screen"

// The upload modal (Views::Uploads::Modals::Upload): files dropped or
// picked join the queue, each with a row that follows its progress, and
// the list behind the modal is reloaded as they start and finish. While
// files go up the screen is kept on, and closing the modal or leaving the
// page asks first, since either stops them.
export default class extends Controller {
  static targets = ["input", "drop", "queue", "template"]
  static outlets = ["confirm-dialog"]
  static values = {
    createUrl: String,
    resultsFrame: String,
    chunkSize: Number,
    words: { type: Object, default: {} }
  }

  connect() {
    this.wording = new Wording(this.wordsValue, document.documentElement.lang)
    this.rows = new Map()
    this.transfers = new Map()
    this.screen = new Screen()
    this.uploader = new Uploader({
      server: new Server(this.createUrlValue),
      memory: new UnfinishedUploads(),
      chunkSize: this.chunkSizeValue,
      listener: this
    })
    document.addEventListener("visibilitychange", this.#visibility)
    window.addEventListener("beforeunload", this.#beforeUnload)
    this.modal = this.element.closest(".modal")
    this.modal?.addEventListener("click", this.#guard, true)
    this.modal?.addEventListener("keydown", this.#guard, true)
    this.modal?.addEventListener("cancel", this.#guard, true)
  }

  disconnect() {
    this.modal?.removeEventListener("click", this.#guard, true)
    this.modal?.removeEventListener("keydown", this.#guard, true)
    this.modal?.removeEventListener("cancel", this.#guard, true)
    window.removeEventListener("beforeunload", this.#beforeUnload)
    document.removeEventListener("visibilitychange", this.#visibility)
    this.screen.letGo()
    this.uploader.stop()
    this.reloadList()
  }

  pick(event) {
    this.enqueue(Array.from(event.target.files))
    event.target.value = ""
  }

  dragOver(event) {
    event.preventDefault()
    this.dropTarget.classList.add("uploader__drop--over")
  }

  dragLeave() {
    this.dropTarget.classList.remove("uploader__drop--over")
  }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    this.enqueue(Array.from(event.dataTransfer?.files || []))
  }

  enqueue(files) {
    files.forEach((file) => this.uploader.add(file))
  }

  pause(event) {
    this.uploader.pause(this.transferOf(event))
  }

  resume(event) {
    this.uploader.resume(this.transferOf(event))
  }

  cancel(event) {
    this.uploader.cancel(this.transferOf(event))
  }

  added(transfer) {
    const row = Row.from(this.templateTarget, transfer.file, this.wording)
    this.rows.set(transfer, row)
    this.transfers.set(row.node, transfer)
    this.queueTarget.appendChild(row.node)
    row.render(transfer)
  }

  changed(transfer) {
    this.rows.get(transfer).render(transfer)
    this.keepScreenOn()
  }

  progressed(transfer) {
    this.rows.get(transfer).progress(transfer)
  }

  listChanged() {
    this.reloadList()
  }

  // The modal's close button, its backdrop, Escape and the back gesture are
  // heard here before modal_controller.js and the browser act on them, and
  // held back while the reader is asked whether to stop what is still going;
  // the modal is closed only on a yes. Escape is stopped as the key is
  // pressed rather than as the dialog's cancel: the browser lets a page
  // refuse a cancel only once between two presses of the reader's, and a
  // second Escape would close the modal without asking. Listened for
  // outside this element and in the capture phase, which is why these are
  // kept as one field: removing a listener needs the same function.
  #guard = (event) => {
    if (!this.uploader.active || !this.#closing(event)) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.askToStop()
  }

  #closing(event) {
    if (event.type === "cancel") return true
    if (event.type === "keydown") return event.key === "Escape"

    return event.target === this.modal || event.target.closest(".modal__close, .modal__btn--cancel, .modal__backdrop")
  }

  async askToStop() {
    const stop = await this.confirmDialogOutlet.ask(this.wording.word("closing"), {
      confirm: this.wording.word("stop"),
      dismiss: this.wording.word("keep"),
      danger: true
    })
    if (stop) this.modal.close()
  }

  #beforeUnload = (event) => {
    if (!this.uploader.active) return

    event.preventDefault()
    event.returnValue = ""
  }

  #visibility = () => {
    if (document.visibilityState === "visible") this.uploader.wake()
    this.keepScreenOn()
  }

  keepScreenOn() {
    this.screen.keepOn(this.uploader.active && document.visibilityState === "visible")
  }

  // The list behind the modal: its frame fetched again from where the page is.
  reloadList() {
    const frame = document.getElementById(this.resultsFrameValue)
    if (!frame) return

    frame.src = window.location.href
    frame.reload()
  }

  transferOf(event) {
    return this.transfers.get(event.target.closest(".uploader__item"))
  }
}
