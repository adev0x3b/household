import { Controller } from "@hotwired/stimulus"
import { interpolate } from "helpers/interpolate"

// The barcode scanner of the bookshelf (Views::Books::Modals::Scan): reads
// the EAN-13 on a book's back cover off the camera and hands the ISBN to
// the lookup form, which asks the server. The browser's own
// BarcodeDetector where it knows ean_13 (Chrome, Android); elsewhere the
// barcode-detector ponyfill (zxing-wasm), loaded only now with import(),
// its wasm from our own assets (wasmUrl), never a CDN. No camera, or no
// permission: a photo of the barcode instead (decodePhoto); the typed ISBN
// is always there. Everything stops in disconnect().
//
// Only a 978/979 EAN-13 whose checksum holds counts, read twice in a row:
// the 5-digit price add-on printed next to it is never an ISBN.
const FORMATS = ["ean_13"]
const ISBN = /^97[89]\d{10}$/

export default class extends Controller {
  static targets = ["viewport", "video", "status", "fallback", "isbn"]
  static values = { wasmUrl: String, messages: Object, interval: { type: Number, default: 120 } }

  async connect() {
    this.stopped = false
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) return this.fallback("no_camera")

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } }
      })
    } catch (error) {
      return this.fallback(error?.name === "NotAllowedError" ? "denied" : "no_camera")
    }
    if (this.stopped) return this.stopStream()

    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play().catch(() => {})
    this.say("loading")
    try {
      this.detector = await this.buildDetector()
    } catch (error) {
      console.warn("[barcode-scanner] no detector", error)
      return this.fallback("no_camera")
    }
    this.say("aim")
    this.scheduleFrame()
  }

  disconnect() {
    this.stopped = true
    this.cancelFrame()
    this.stopStream()
    this.detector = null
  }

  // A photo of the barcode, decoded with the same detector.
  async decodePhoto(event) {
    const file = event.target.files?.[0]
    if (!file) return

    try {
      this.detector ||= await this.buildDetector()
      const bitmap = await createImageBitmap(file)
      const codes = await this.detector.detect(bitmap)
      bitmap.close?.()
      const isbn = this.isbnIn(codes)
      isbn ? this.accept(isbn) : this.say("none_in_photo")
    } catch (error) {
      console.warn("[barcode-scanner] photo not decoded", error)
      this.say("none_in_photo")
    }
    event.target.value = ""
  }

  async buildDetector() {
    if ("BarcodeDetector" in window) {
      const supported = await window.BarcodeDetector.getSupportedFormats().catch(() => [])
      if (FORMATS.every((format) => supported.includes(format))) return new window.BarcodeDetector({ formats: FORMATS })
    }

    const { BarcodeDetector, prepareZXingModule } = await import("barcode-detector/ponyfill")
    // Before the first detect(), which is when the module instantiates:
    // the ponyfill would otherwise fetch its wasm from a CDN.
    prepareZXingModule({
      overrides: { locateFile: (path, prefix) => (path.endsWith(".wasm") ? this.wasmUrlValue : prefix + path) }
    })
    return new BarcodeDetector({ formats: FORMATS })
  }

  scheduleFrame() {
    if (this.stopped) return

    const video = this.videoTarget
    this.frameHandle = video.requestVideoFrameCallback
      ? video.requestVideoFrameCallback(() => this.scan())
      : requestAnimationFrame(() => this.scan())
    this.frameIsVideoCallback = !!video.requestVideoFrameCallback
  }

  cancelFrame() {
    if (!this.frameHandle) return
    if (this.frameIsVideoCallback) this.videoTarget.cancelVideoFrameCallback?.(this.frameHandle)
    else cancelAnimationFrame(this.frameHandle)
    this.frameHandle = null
  }

  // detect() is costly: a few frames a second are plenty for a still barcode.
  async scan() {
    if (this.stopped) return
    const video = this.videoTarget
    const now = performance.now()
    if (this.busy || document.hidden || video.readyState < 2 || now - (this.lastAt || 0) < this.intervalValue) {
      return this.scheduleFrame()
    }

    this.lastAt = now
    this.busy = true
    try {
      const isbn = this.isbnIn(await this.detector.detect(video))
      if (isbn) {
        if (this.candidate === isbn) return this.accept(isbn)
        this.candidate = isbn
      }
    } catch {
      // one frame can fail to decode; the next may not
    } finally {
      this.busy = false
    }
    this.scheduleFrame()
  }

  isbnIn(codes) {
    return codes.map((code) => code.rawValue).find((value) => ISBN.test(value) && this.checksumOk(value))
  }

  accept(isbn) {
    this.stopped = true
    this.cancelFrame()
    this.stopStream()
    navigator.vibrate?.(60)
    this.say("found", { isbn })
    this.isbnTarget.value = isbn
    this.element.requestSubmit()
  }

  fallback(reason) {
    this.say(reason)
    this.viewportTarget.hidden = true
    this.fallbackTarget.hidden = false
  }

  say(key, values = {}) {
    this.statusTarget.textContent = interpolate(this.messagesValue[key] || "", values)
  }

  stopStream() {
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    this.videoTarget.srcObject = null
  }

  checksumOk(digits) {
    return [...digits].reduce((sum, char, index) => sum + Number(char) * (index % 2 ? 3 : 1), 0) % 10 === 0
  }
}
