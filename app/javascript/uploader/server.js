import { csrfToken } from "helpers/csrf"

// The connection went while a chunk was on its way: the kind of failure
// that is tried again.
export class ConnectionLost extends Error {}

// The page stopped the chunk itself: a pause, a cancel, the modal closing.
export class Aborted extends Error {}

// What the proxy in front answers while the app restarts (a deploy): the
// app will be back, so it is tried again like a lost connection.
const UNAVAILABLE = [502, 503, 504]

// What a chunk refused because the upload is past taking them says of it:
// the whole file is in, its answer having been lost on the way.
const ALL_IN = ["processing", "ready"]

// The upload's side of the server (UploadsController, UploadChunksController):
// a POST makes the upload with its size declared, a POST of each chunk
// appends it at the offset the server has reached, a GET of its progress
// says where to go on from, a DELETE takes it away. XMLHttpRequest for the chunks, not fetch: it
// reports upload progress.
export class Server {
  constructor(createUrl) {
    this.createUrl = createUrl
  }

  async create(file) {
    const response = await fetch(this.createUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ name: file.name, byte_size: file.size, content_type: file.type })
    })
    // A refusal is JSON with its reason, unless something before the app
    // answered (a proxy's page): then the status line is all there is.
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || response.statusText)

    return data
  }

  // Where an upload stands, or null when the server no longer has it.
  async progress(url) {
    const response = await fetch(url, { headers: { Accept: "application/json" } }).catch(() => {
      throw new ConnectionLost()
    })
    if (response.status === 404) return null
    if (UNAVAILABLE.includes(response.status)) throw new ConnectionLost()
    if (!response.ok) throw new Error(String(response.status))

    return response.json()
  }

  // Resolves with the offset to go on from: after the chunk, or, when the
  // server disagrees on where the file stands (a chunk that did arrive, or
  // one its disk lost), the offset it names, so the file goes on from
  // there and never a byte is skipped. A last chunk sent again after its
  // answer was lost finds the whole file in, and resolves with its end.
  sendChunk({ url, offset, chunk, signal, onProgress }) {
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest()
      request.open("POST", url)
      request.setRequestHeader("Content-Type", "application/offset+octet-stream")
      request.setRequestHeader("Upload-Offset", String(offset))
      request.setRequestHeader("X-CSRF-Token", csrfToken())
      request.setRequestHeader("Accept", "application/json")
      request.upload.onprogress = (event) => {
        if (event.lengthComputable) onProgress(offset + event.loaded)
      }
      request.onload = () => {
        const reached = Number(request.getResponseHeader("Upload-Offset"))
        if (request.status === 204) {
          resolve(Number.isFinite(reached) ? reached : offset + chunk.size)
        } else if (request.status === 409 && Number.isFinite(reached)) {
          resolve(reached)
        } else if (request.status === 422 && allIn(request) && Number.isFinite(reached)) {
          resolve(reached)
        } else if (UNAVAILABLE.includes(request.status)) {
          reject(new ConnectionLost())
        } else {
          reject(new Error(errorIn(request)))
        }
      }
      request.onerror = () => reject(new ConnectionLost())
      request.ontimeout = () => reject(new ConnectionLost())
      request.onabort = () => reject(new Aborted())
      signal.addEventListener("abort", () => request.abort())
      request.send(chunk)
    })
  }

  destroy(url) {
    return fetch(url, {
      method: "DELETE",
      headers: { "X-CSRF-Token": csrfToken(), Accept: "text/vnd.turbo-stream.html" }
    })
  }
}

// The reason the app gives, else the status alone: an answer from before
// the app (a proxy's page) is not JSON.
function errorIn(request) {
  return answer(request).error || String(request.status)
}

function allIn(request) {
  return ALL_IN.includes(answer(request).status)
}

function answer(request) {
  try {
    return JSON.parse(request.responseText) || {}
  } catch {
    return {}
  }
}
