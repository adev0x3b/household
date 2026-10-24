// A file that was picked before and not finished is recognised by its
// name, size and modification time, and goes on from where the server has
// it, after a reload or on another day. A file is kept a day: the server
// sweeps an upload nobody finishes after as long.
const KEY = "household:uploads"
const KEPT_FOR = 24 * 60 * 60 * 1000

export class UnfinishedUploads {
  constructor({ storage = window.localStorage, now = () => Date.now() } = {}) {
    this.storage = storage
    this.now = now
  }

  recall(file) {
    return this.read()[fingerprint(file)] || null
  }

  remember(file, upload) {
    const memory = this.read()
    memory[fingerprint(file)] = { ...upload, at: this.now() }
    this.write(memory)
  }

  forget(file) {
    const memory = this.read()
    delete memory[fingerprint(file)]
    this.write(memory)
  }

  read() {
    try {
      return JSON.parse(this.storage.getItem(KEY) || "{}")
    } catch {
      // Storage refused (a private window) or holds something else: nothing is remembered.
      return {}
    }
  }

  write(memory) {
    const kept = Object.fromEntries(
      Object.entries(memory).filter(([, upload]) => this.now() - (upload.at || 0) < KEPT_FOR)
    )
    try {
      this.storage.setItem(KEY, JSON.stringify(kept))
    } catch {
      // Storage full or refused: the upload still goes, it is only not resumable later.
    }
  }
}

function fingerprint(file) {
  return `${file.name}:${file.size}:${file.lastModified}`
}
