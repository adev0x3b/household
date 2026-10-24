import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// An eval run followed live (Views::Assistant::Evals::LiveRun): while
// the run lasts, it asks every second for the events after the last one
// seen (RunsController#events) and applies the Turbo Streams that come
// back, and it counts the seconds since the last event on the status card.
// It polls rather than listening on Action Cable because the run is a
// process of its own that writes its events to a file and broadcasts
// nothing (AssistantEval::RunEvents); asking from a cursor also means a
// page that was away or reloaded misses none of them.
export default class extends Controller {
  static targets = ["status", "clock", "timeline"]
  static values = { url: String, after: Number, active: Boolean, interval: { type: Number, default: 1000 } }

  connect() {
    this.tick = setInterval(() => this.updateClock(), 1000)
    this.updateClock()
    if (this.activeValue) this.schedule()
  }

  disconnect() {
    clearInterval(this.tick)
    clearTimeout(this.timer)
    this.stopped = true
  }

  schedule() {
    this.timer = setTimeout(() => this.poll(), this.intervalValue)
  }

  async poll() {
    if (this.stopped) return
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("after", this.afterValue)
      const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      if (response.ok) {
        const stickToBottom = this.nearBottom()
        Turbo.renderStreamMessage(await response.text())
        this.afterValue = Number(response.headers.get("Eval-Events-Next") || this.afterValue)
        this.activeValue = response.headers.get("Eval-Run-Active") === "true"
        // The status card (and the clock in it) was just replaced: fill it in now.
        requestAnimationFrame(() => this.updateClock())
        if (stickToBottom) this.scrollToBottom()
      }
    } catch {
      // The dev server restarting mid-run: try again next tick.
    }
    if (this.activeValue) this.schedule()
    else this.updateClock()
  }

  // "waiting on the model · 42 s" while the run is inside a turn.
  updateClock() {
    if (!this.hasClockTarget || !this.hasStatusTarget) return
    const { lastAt, phase } = this.statusTarget.dataset
    if (!this.activeValue || !phase || !lastAt) {
      this.clockTarget.textContent = ""
      return
    }
    const seconds = Math.max(0, Math.round(Date.now() / 1000 - Number(lastAt)))
    this.clockTarget.textContent = `${phase} · ${seconds} s`
  }

  // Follow new events only when the reader is already at the end.
  nearBottom() {
    return window.innerHeight + window.scrollY >= document.body.scrollHeight - 200
  }

  scrollToBottom() {
    window.scrollTo({ top: document.body.scrollHeight })
  }
}
