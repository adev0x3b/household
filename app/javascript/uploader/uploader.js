import { Transfer } from "uploader/transfer"
import { ConnectionLost, Aborted } from "uploader/server"

// A connection lost this many times in a row, waiting longer each time, is gone.
const RETRIES = 5
// How often a file being checked by the server is asked after.
const POLL = 2000

// The queue of files going up, one at a time so that a phone's connection
// is not shared between them, each in chunks the server appends at the
// offset it has reached. A file picked before and not finished goes on
// from where the server has it. A chunk lost to the connection is sent
// again, unless the page is in the background: a phone pauses a page
// there, so the file waits to be seen again instead, with nothing counted
// against it. What happens on the page is the listener's.
export class Uploader {
  constructor({ server, memory, chunkSize, listener, delay = wait, hidden = pageHidden }) {
    this.server = server
    this.memory = memory
    this.chunkSize = chunkSize
    this.listener = listener
    this.delay = delay
    this.hidden = hidden
    this.transfers = []
    this.running = false
    this.waiting = []
    this.stopped = false
  }

  add(file) {
    const transfer = new Transfer(file)
    this.transfers.push(transfer)
    this.listener.added(transfer)
    this.next()
    return transfer
  }

  get active() {
    return this.transfers.some((transfer) => transfer.active)
  }

  pause(transfer) {
    if (!transfer.uploading) return

    transfer.pause()
    this.listener.changed(transfer)
    transfer.request?.abort()
  }

  resume(transfer) {
    if (!transfer.resumable) return

    transfer.requeue()
    this.listener.changed(transfer)
    this.next()
  }

  async cancel(transfer) {
    if (!transfer.cancellable) return

    transfer.cancel()
    transfer.request?.abort()
    this.listener.changed(transfer)
    this.memory.forget(transfer.file)
    if (!transfer.upload) return

    // The server sweeps an upload nobody finishes after a day anyway.
    await this.server.destroy(transfer.upload.url).catch(() => {})
    this.listener.listChanged()
  }

  // The page is seen again: what waited for it goes on, and what gave up
  // on a connection lost in the background starts over from where the
  // server has it.
  wake() {
    this.transfers.forEach((transfer) => {
      if (transfer.failed && transfer.lostConnection) {
        transfer.requeue()
        this.listener.changed(transfer)
      }
    })
    this.waiting.splice(0).forEach((resume) => resume())
    this.next()
  }

  stop() {
    this.stopped = true
    this.transfers.forEach((transfer) => transfer.request?.abort())
  }

  async next() {
    if (this.running || this.stopped) return
    const transfer = this.transfers.find((candidate) => candidate.queued)
    if (!transfer) return

    this.running = true
    try {
      await this.send(transfer)
    } finally {
      this.running = false
      this.next()
    }
  }

  async send(transfer) {
    try {
      transfer.start()
      this.listener.changed(transfer)
      if (!transfer.upload) transfer.startFrom((await this.recall(transfer)) || (await this.create(transfer)))
      transfer.progress(transfer.offset)
      this.listener.progressed(transfer)
      this.listener.listChanged()
      while (!transfer.finished && transfer.uploading) await this.sendChunk(transfer)
      if (!transfer.uploading) return

      this.memory.forget(transfer.file)
      transfer.finishSending()
      this.listener.changed(transfer)
      this.watch(transfer)
    } catch (error) {
      // Paused or cancelled: the file is already in the state the reader gave it.
      if (error instanceof Aborted) return

      transfer.fail(error instanceof ConnectionLost ? null : error.message)
      this.listener.changed(transfer)
    }
  }

  // The same file picked before and not finished: where it got to, as long
  // as the server still has it and still waits for the rest.
  async recall(transfer) {
    const remembered = this.memory.recall(transfer.file)
    if (!remembered) return null

    const progress = await this.server.progress(remembered.progress_url)
    if (progress?.status !== "uploading") return null

    return { ...remembered, ...progress }
  }

  async create(transfer) {
    const upload = await this.server.create(transfer.file)
    this.memory.remember(transfer.file, upload)
    return upload
  }

  async sendChunk(transfer) {
    const size = this.chunkSize || transfer.upload.chunk_size
    const start = transfer.offset
    const chunk = transfer.file.slice(start, Math.min(start + size, transfer.file.size))
    transfer.request = new AbortController()
    try {
      const offset = await this.server.sendChunk({
        url: transfer.upload.chunk_url,
        offset: start,
        chunk,
        signal: transfer.request.signal,
        onProgress: (bytes) => {
          transfer.progress(bytes)
          this.listener.progressed(transfer)
        }
      })
      transfer.advance(offset)
      this.listener.progressed(transfer)
    } catch (error) {
      if (!(error instanceof ConnectionLost)) throw error

      await this.waitToRetry(transfer)
    } finally {
      transfer.request = null
    }
  }

  // A little longer each time, up to RETRIES, then the connection is gone.
  // Lost while the page is in the background: wait to be seen again,
  // without counting, since nothing would get through from there anyway.
  async waitToRetry(transfer) {
    if (this.hidden()) {
      transfer.waitForTheForeground()
      this.listener.changed(transfer)
      await new Promise((resume) => this.waiting.push(resume))
      return
    }
    if (transfer.attempts >= RETRIES) throw new ConnectionLost()

    transfer.retry()
    this.listener.changed(transfer)
    await this.delay(1000 * 2 ** (transfer.attempts - 1))
  }

  // Until the server has checked the file, while the next one goes up. A
  // file the server found short is sent the rest of, one it gave up on is
  // lost, and a poll that fails is simply made again.
  async watch(transfer) {
    while (transfer.processing && !this.stopped) {
      await this.delay(POLL)
      if (!transfer.processing || this.stopped) return

      let progress
      try {
        progress = await this.server.progress(transfer.upload.progress_url)
      } catch {
        continue
      }
      if (progress === null) {
        transfer.lose()
        this.listener.changed(transfer)
        this.listener.listChanged()
      } else if (progress.status === "ready") {
        transfer.finish()
        this.listener.changed(transfer)
        this.listener.progressed(transfer)
        this.listener.listChanged()
      } else if (progress.status === "uploading") {
        transfer.offset = progress.offset
        transfer.requeue()
        this.listener.changed(transfer)
        this.next()
      }
    }
  }
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function pageHidden() {
  return document.visibilityState === "hidden"
}
