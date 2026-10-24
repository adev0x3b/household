import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Brings the page up to date when it may have missed live updates (the
// layout's body): when the browser shows it again from its back-forward
// cache, and when the live connection comes back after a drop, as it does
// once a phone has slept. The refresh is Turbo's page refresh, a morph that
// keeps the scroll, and it leaves the kept targets (the open modal, the
// toasts) and what the reader typed or opened as they are. A refresh the
// server pushes because someone else changed the page is kept the same way.
export default class extends Controller {
  static targets = ["kept"]

  #streams = null
  #seenConnected = new WeakSet()
  #refreshAsked = false
  #refreshing = false

  // A page the browser kept whole while the reader was on another site
  // comes back as it was left, and Turbo isn't asked.
  #restored = (event) => {
    if (event.persisted) this.#refresh()
  }

  // Each live stream (turbo_stream_from) is marked "connected" once its
  // subscription is confirmed, and unmarked when the connection drops. One
  // marked again has been away, and what was pushed meanwhile is lost.
  #streamsChanged = (records) => {
    let reconnected = false
    for (const { target } of records) {
      if (!target.hasAttribute("connected")) continue
      if (this.#seenConnected.has(target)) reconnected = true
      this.#seenConnected.add(target)
    }
    if (reconnected) this.#refresh()
  }

  // A refresh asked for is only a request. Turbo waits a moment, then leaves
  // it out when a visit is already on its way or when it is the echo of a
  // change made from this page, so the ask alone doesn't say one is coming.
  #pushedRefresh = (event) => {
    if (event.target.action === "refresh") this.#refreshAsked = true
  }

  // What the reader asks for next is theirs. A refresh asked for before a
  // press is answered is that press's echo, or one its answer brings anyway,
  // and one asked for before a click gives way to the page clicked. This is
  // also what clears an ask Turbo left out.
  #readerAsked = () => {
    this.#refreshAsked = false
  }

  // Turbo carries a refresh out as a visit of its own, so the visit that
  // follows an ask, with nothing the reader asked for in between, is it.
  #visitStarted = () => {
    this.#refreshing = this.#refreshAsked
    this.#refreshAsked = false
  }

  #keepKeptTargets = (event) => {
    if (this.#refreshing && this.keptTargets.includes(event.target)) event.preventDefault()
  }

  // What the reader changed stays as they left it: a field's value or
  // tick, against the page sent back with the field as it was saved, and
  // a section they opened or closed.
  #keepReadersChanges = (event) => {
    if (!this.#refreshing) return

    const element = event.target
    const { attributeName } = event.detail
    const typed = attributeName === "value" && "defaultValue" in element && element.value !== element.defaultValue
    const ticked =
      attributeName === "checked" && "defaultChecked" in element && element.checked !== element.defaultChecked
    const folded = attributeName === "open" && element instanceof HTMLDetailsElement
    if (typed || ticked || folded) event.preventDefault()
  }

  #refreshed = () => {
    this.#refreshing = false
  }

  connect() {
    this.element
      .querySelectorAll("turbo-cable-stream-source[connected]")
      .forEach((source) => this.#seenConnected.add(source))
    this.#streams = new MutationObserver(this.#streamsChanged)
    this.#streams.observe(this.element, { subtree: true, attributeFilter: ["connected"] })
    window.addEventListener("pageshow", this.#restored)
    document.addEventListener("turbo:before-stream-render", this.#pushedRefresh)
    document.addEventListener("turbo:submit-end", this.#readerAsked)
    document.addEventListener("turbo:click", this.#readerAsked)
    document.addEventListener("turbo:visit", this.#visitStarted)
    document.addEventListener("turbo:before-morph-element", this.#keepKeptTargets)
    document.addEventListener("turbo:before-morph-attribute", this.#keepReadersChanges)
    document.addEventListener("turbo:load", this.#refreshed)
  }

  disconnect() {
    this.#streams.disconnect()
    window.removeEventListener("pageshow", this.#restored)
    document.removeEventListener("turbo:before-stream-render", this.#pushedRefresh)
    document.removeEventListener("turbo:submit-end", this.#readerAsked)
    document.removeEventListener("turbo:click", this.#readerAsked)
    document.removeEventListener("turbo:visit", this.#visitStarted)
    document.removeEventListener("turbo:before-morph-element", this.#keepKeptTargets)
    document.removeEventListener("turbo:before-morph-attribute", this.#keepReadersChanges)
    document.removeEventListener("turbo:load", this.#refreshed)
  }

  // What Turbo's own refresh stream action calls: it leaves a visit already
  // on its way alone, since that one brings a fresh page too.
  #refresh() {
    this.#refreshAsked = true
    Turbo.session.refresh(document.baseURI)
  }
}
