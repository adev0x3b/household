// The installed app, page side: it registers the service worker the layout
// names, and keeps the browser's offer to install for install_controller.js.
// Chromium makes that offer once, often before any controller has connected,
// so a module loaded with the page is what has to catch it.
let installPrompt = null

export const INSTALLABLE_EVENT = "pwa:installable"

export function pendingInstallPrompt() {
  return installPrompt
}

export function forgetInstallPrompt() {
  installPrompt = null
}

// Running as the installed app rather than in a browser tab.
export function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
}

// iPhone and iPad (iPadOS says it's a Mac): no install prompt, and push only once installed.
export function isIos() {
  return (
    /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  )
}

// Never from the HTTP cache: a new version must be seen on the next visit.
export async function registerServiceWorker() {
  const meta = document.querySelector('meta[name="service-worker"]')
  if (!meta || !("serviceWorker" in navigator)) return null

  try {
    return await navigator.serviceWorker.register(meta.content, { scope: meta.dataset.scope, updateViaCache: "none" })
  } catch (error) {
    console.warn("[pwa] service worker not registered", error)
    return null
  }
}

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault()
  installPrompt = event
  window.dispatchEvent(new CustomEvent(INSTALLABLE_EVENT))
})

window.addEventListener("appinstalled", forgetInstallPrompt)

registerServiceWorker()
