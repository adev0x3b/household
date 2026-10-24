import { Controller } from "@hotwired/stimulus"

// A row that scrolls sideways (Components::ScrollRow): the element is
// marked is-more-start and is-more-end while the row inside it, its first
// child, has content past that edge, and the stylesheet fades that edge.
// The marks follow the row's scrolling, its size, and its chips changing
// under a morph.
export default class extends Controller {
  #row
  #resizes
  #changes

  #update = () => {
    const row = this.#row
    const hidden = row.scrollWidth - row.clientWidth - row.scrollLeft

    this.element.classList.toggle("is-more-start", row.scrollLeft > 1)
    this.element.classList.toggle("is-more-end", hidden > 1)
  }

  connect() {
    this.#row = this.element.firstElementChild
    this.#row.addEventListener("scroll", this.#update, { passive: true })
    this.#resizes = new ResizeObserver(this.#update)
    this.#resizes.observe(this.#row)
    this.#changes = new MutationObserver(this.#update)
    this.#changes.observe(this.#row, { childList: true })
    this.#update()
  }

  disconnect() {
    this.#row.removeEventListener("scroll", this.#update)
    this.#resizes.disconnect()
    this.#changes.disconnect()
  }
}
