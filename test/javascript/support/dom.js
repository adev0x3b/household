import { JSDOM } from "jsdom"

// Node has no DOM, and Stimulus and the controllers read the browser's
// globals. A jsdom window stands in for the page; a test file imports this
// before them, so the globals are there when they load. The page is in the
// front tab, as the reader sees it.
const { window } = new JSDOM("<!doctype html><html><head></head><body></body></html>", {
  url: "https://household.test/",
  pretendToBeVisual: true
})

// jsdom has no media queries. None matches, as on a computer with a mouse.
window.matchMedia = (query) => ({ media: query, matches: false })

// Nor does it lay a page out, so there is nothing to scroll.
window.Element.prototype.scrollIntoView = () => {}

const GLOBALS = [
  "window",
  "document",
  "location",
  "history",
  "customElements",
  "Node",
  "Element",
  "HTMLElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLDetailsElement",
  "FormData",
  "File",
  "MutationObserver",
  "Event",
  "CustomEvent",
  "KeyboardEvent",
  "MouseEvent",
  "FocusEvent"
]

// What a browser's scripts call without naming the window, as Turbo does.
const WINDOW_FUNCTIONS = ["addEventListener", "removeEventListener", "requestAnimationFrame", "cancelAnimationFrame"]

for (const name of GLOBALS) globalThis[name] = window[name]
for (const name of WINDOW_FUNCTIONS) globalThis[name] = window[name].bind(window)
