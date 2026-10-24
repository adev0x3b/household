// Bytes a second over the last seconds, which is what a reader wants to
// see: the whole file's average would hide a connection that just slowed.
// Nothing is said until a second has been measured.
const WINDOW = 8000
const LEAST = 1000

export class Speedometer {
  constructor(now = () => performance.now()) {
    this.now = now
    this.samples = []
  }

  record(bytes) {
    const at = this.now()
    this.samples.push({ at, bytes })
    while (this.samples.length > 2 && at - this.samples[0].at > WINDOW) this.samples.shift()
  }

  reset() {
    this.samples = []
  }

  get bytesPerSecond() {
    const first = this.samples[0]
    const last = this.samples[this.samples.length - 1]
    if (!first || last.at - first.at < LEAST) return null

    const speed = ((last.bytes - first.bytes) * 1000) / (last.at - first.at)
    return speed > 0 ? speed : null
  }
}
