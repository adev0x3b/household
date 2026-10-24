import { Speedometer } from "uploader/speedometer"

// What a file in the queue is doing. The words are also the row's
// data-state, which its stylesheet reads, and the keys of the words the
// view translated for each state.
export const State = Object.freeze({
  QUEUED: "queued",
  UPLOADING: "uploading",
  PROCESSING: "processing",
  READY: "ready",
  PAUSED: "paused",
  FAILED: "failed",
  CANCELLED: "cancelled"
})

// One file on its way up: its state, how far it has got, and what the
// server knows of it once it has a row there. A notice is a line shown in
// place of the state's word while it holds ("retrying…"), and goes with
// the next change of state.
export class Transfer {
  constructor(file) {
    this.file = file
    this.state = State.QUEUED
    this.notice = null
    this.upload = null
    this.offset = 0
    this.sent = 0
    this.attempts = 0
    this.lostConnection = false
    this.speedometer = new Speedometer()
  }

  get queued() {
    return this.state === State.QUEUED
  }

  get uploading() {
    return this.state === State.UPLOADING
  }

  get processing() {
    return this.state === State.PROCESSING
  }

  get ready() {
    return this.state === State.READY
  }

  get failed() {
    return this.state === State.FAILED
  }

  // Still to be sent, or being sent: what keeps the screen on and the
  // modal from closing without a word.
  get active() {
    return this.queued || this.uploading
  }

  get resumable() {
    return this.state === State.PAUSED || this.state === State.FAILED
  }

  get cancellable() {
    return this.state !== State.READY && this.state !== State.CANCELLED
  }

  // Whether its size alone describes it: not started, or nothing left to send.
  get settled() {
    return this.ready || this.processing || (this.queued && this.sent === 0)
  }

  get percent() {
    if (this.file.size === 0) return 100

    return Math.min(100, Math.floor((this.sent * 100) / this.file.size))
  }

  get finished() {
    return this.offset >= this.file.size
  }

  get speed() {
    return this.speedometer.bytesPerSecond
  }

  start() {
    this.become(State.UPLOADING)
    this.speedometer.reset()
  }

  startFrom(upload) {
    this.upload = upload
    this.offset = upload.offset
  }

  progress(bytes) {
    this.sent = bytes
    this.speedometer.record(bytes)
  }

  advance(offset) {
    this.offset = offset
    this.attempts = 0
    this.progress(offset)
  }

  // Another go after the connection went; the count holds until a chunk
  // gets through, so a connection that keeps dropping is given up on.
  retry() {
    this.attempts += 1
    this.speedometer.reset()
    this.say("retrying")
  }

  waitForTheForeground() {
    this.speedometer.reset()
    this.say("background")
  }

  pause() {
    this.become(State.PAUSED)
  }

  requeue() {
    this.attempts = 0
    this.lostConnection = false
    this.become(State.QUEUED)
  }

  finishSending() {
    this.become(State.PROCESSING)
  }

  finish() {
    this.become(State.READY)
    this.progress(this.file.size)
  }

  // With the server's reason, or with none when the connection was lost
  // for good: then the page is to blame for nothing, and tries again by
  // itself once it is seen again.
  fail(reason = null) {
    this.lostConnection = reason === null
    this.become(State.FAILED)
    if (reason !== null) this.say("failed_with", { reason })
  }

  // The server no longer has it (its check failed for a day, or it was
  // deleted elsewhere): resumed, it goes up again from the start.
  lose() {
    this.upload = null
    this.offset = 0
    this.sent = 0
    this.lostConnection = false
    this.become(State.FAILED)
    this.say("gone")
  }

  cancel() {
    this.become(State.CANCELLED)
  }

  say(key, values = {}) {
    this.notice = { key, values }
  }

  become(state) {
    this.state = state
    this.notice = null
  }
}
