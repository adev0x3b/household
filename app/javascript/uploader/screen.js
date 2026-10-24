// Keeps the screen on while files go up: a phone that sleeps puts the
// browser in the background, and no browser lets a page send a file from
// there. Let go when they are done, or when the page is hidden anyway.
export class Screen {
  constructor() {
    this.lock = null
    this.requesting = false
  }

  async keepOn(wanted) {
    if (!wanted) return this.letGo()
    if (this.lock || this.requesting || !("wakeLock" in navigator)) return

    this.requesting = true
    try {
      this.lock = await navigator.wakeLock.request("screen")
      this.lock.addEventListener("release", () => {
        this.lock = null
      })
    } catch {
      // Refused (battery saver, a page without focus): the uploads go on all the same.
      this.lock = null
    } finally {
      this.requesting = false
    }
  }

  letGo() {
    this.lock?.release().catch(() => {})
    this.lock = null
  }
}
