import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "helpers/csrf"
import { isStandalone, isIos } from "pwa"

// The "Notifications" switch in the navbar's "This device"
// (Views::Layouts::DeviceSettings): Web Push for this browser, for whoever is
// signed in. It's on when the browser holds a subscription the server has
// for this person (digests of their endpoints, so a phone that was someone
// else's isn't shown as on). Permission is only asked when the switch is
// turned on: browsers require a tap for it.
export default class extends Controller {
  static targets = ["switch", "status"]
  static values = { publicKey: String, url: String, digests: Array, labels: Object }

  async connect() {
    this.subscribed = false
    this.state = this.unavailableState()
    if (this.state) return this.render()

    try {
      this.registration = await navigator.serviceWorker.ready
      const subscription = await this.registration.pushManager.getSubscription()
      this.subscribed = !!subscription && this.digestsValue.includes(await digest(subscription.endpoint))
    } catch (error) {
      console.warn("[push] can't read this device's subscription", error)
    }
    this.render()
  }

  async toggle() {
    this.switchTarget.disabled = true
    try {
      this.subscribed ? await this.unsubscribe() : await this.subscribe()
    } catch (error) {
      console.warn("[push] couldn't change this device's notifications", error)
    }
    this.render()
  }

  async subscribe() {
    if ((await Notification.requestPermission()) !== "granted") return

    let response = await this.send("POST", { subscription: (await this.browserSubscription()).toJSON() })
    // The server keeps this browser's subscription for someone else and
    // can't tell it is this browser: a new subscription, with an endpoint of
    // its own, is one nobody else holds.
    if (response.status === 409) {
      await (await this.registration.pushManager.getSubscription()).unsubscribe()
      response = await this.send("POST", { subscription: (await this.browserSubscription()).toJSON() })
    }
    this.subscribed = response.ok
  }

  async browserSubscription() {
    const pushManager = this.registration.pushManager
    return (
      (await pushManager.getSubscription()) ||
      (await pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: base64UrlToBytes(this.publicKeyValue)
      }))
    )
  }

  async unsubscribe() {
    const subscription = await this.registration.pushManager.getSubscription()
    if (subscription) {
      await this.send("DELETE", { endpoint: subscription.endpoint })
      await subscription.unsubscribe()
    }
    this.subscribed = false
  }

  send(method, body) {
    return fetch(this.urlValue, {
      method,
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify(body)
    })
  }

  // Why this browser can't, before trying: iOS outside the installed app,
  // or no Push API at all.
  unavailableState() {
    if (isIos() && !isStandalone()) return "install_first"
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) {
      return "unsupported"
    }
    return null
  }

  render() {
    const state = this.state || (Notification.permission === "denied" ? "denied" : this.subscribed ? "on" : "off")
    this.statusTarget.textContent = this.labelsValue[state] || ""
    this.switchTarget.checked = state === "on"
    this.switchTarget.disabled = !["on", "off"].includes(state)
  }
}

async function digest(text) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("")
}

function base64UrlToBytes(text) {
  const base64 = (text + "=".repeat((4 - (text.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/")
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
}
