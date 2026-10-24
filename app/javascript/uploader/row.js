// A file's row in the upload modal, made from the view's template, and
// its row on the list behind the modal when that is on the page. The
// figures are redrawn a few times a second at most: progress events come
// far faster than a reader can follow.
const REDRAW = 250

export class Row {
  constructor(node, wording) {
    this.node = node
    this.wording = wording
    this.drawnAt = 0
  }

  static from(template, file, wording) {
    const node = template.content.firstElementChild.cloneNode(true)
    node.querySelector("[data-role=name]").textContent = file.name
    node.querySelector("[data-role=bar]").setAttribute("aria-label", file.name)
    return new Row(node, wording)
  }

  // The state changed: everything about the row is redrawn.
  render(transfer) {
    this.node.dataset.state = transfer.state
    this.node.querySelector("[data-role=status]").textContent = this.wording.status(transfer)
    this.figures(transfer, { force: true })
  }

  // Bytes moved: the bar, the figures, and the row behind.
  progress(transfer) {
    const bar = this.node.querySelector("[data-role=bar]")
    bar.style.setProperty("--progress-bar-value", `${transfer.percent}%`)
    bar.setAttribute("aria-valuenow", String(transfer.percent))
    bar.classList.toggle("is-done", transfer.percent >= 100)
    this.figures(transfer)
    this.behind(transfer)
  }

  figures(transfer, { force = false } = {}) {
    const now = performance.now()
    if (!force && now - this.drawnAt < REDRAW) return

    this.drawnAt = now
    this.node.querySelector("[data-role=stats]").textContent = this.wording.figures(transfer)
  }

  behind(transfer) {
    const row = transfer.upload && document.getElementById(`upload_${transfer.upload.id}`)
    if (!row) return

    const bar = row.querySelector(".progress-bar")
    bar?.style.setProperty("--progress-bar-value", `${transfer.percent}%`)
    bar?.setAttribute("aria-valuenow", String(transfer.sent))
    const label = row.querySelector(".upload-row__status .status-badge span")
    if (label) label.textContent = this.wording.rowStatus(transfer.percent)
  }
}
