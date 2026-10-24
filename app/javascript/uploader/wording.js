import { interpolate } from "helpers/interpolate"

const UNITS = ["B", "KB", "MB", "GB", "TB"]

// What the upload modal says, from the phrases the view translated: the
// state of a file, a notice about it, and its line of figures.
export class Wording {
  constructor(words, locale) {
    this.words = words
    this.locale = locale
  }

  word(key) {
    return this.words[key] || key
  }

  phrase(key, values) {
    return interpolate(this.word(key), values)
  }

  status(transfer) {
    if (transfer.notice) return this.phrase(transfer.notice.key, transfer.notice.values)

    return this.word(transfer.state)
  }

  // "38% · 0.9 GB of 2.3 GB · 8.4 MB/s · 3 min left" while it goes, the
  // size alone before and after.
  figures(transfer) {
    if (transfer.settled) return this.size(transfer.file.size)

    const parts = [
      this.phrase("progress", {
        percent: transfer.percent,
        sent: this.size(transfer.sent),
        total: this.size(transfer.file.size)
      })
    ]
    const speed = transfer.uploading ? transfer.speed : null
    if (speed) {
      parts.push(this.phrase("speed", { speed: this.size(speed) }))
      parts.push(this.timeLeft((transfer.file.size - transfer.sent) / speed))
    }
    return parts.join(" · ")
  }

  timeLeft(seconds) {
    if (!Number.isFinite(seconds)) return ""
    if (seconds < 60) return this.phrase("eta_seconds", { count: Math.max(1, Math.ceil(seconds)) })
    if (seconds < 3600) return this.phrase("eta_minutes", { count: Math.ceil(seconds / 60) })

    const minutes = Math.ceil(seconds / 60)
    return this.phrase("eta_hours", { hours: Math.floor(minutes / 60), minutes: minutes % 60 })
  }

  // The file's row on the page behind: "Uploading, 38%".
  rowStatus(percent) {
    return this.phrase("row", { percent })
  }

  // Sizes as the server writes them (powers of 1024), in the page's language.
  size(bytes) {
    let value = bytes
    let unit = 0
    while (value >= 1024 && unit < UNITS.length - 1) {
      value /= 1024
      unit += 1
    }
    const digits = unit === 0 ? 0 : value < 10 ? 1 : 0
    const number = new Intl.NumberFormat(this.locale || undefined, {
      maximumFractionDigits: digits,
      minimumFractionDigits: digits
    }).format(value)
    return `${number} ${UNITS[unit]}`
  }
}
