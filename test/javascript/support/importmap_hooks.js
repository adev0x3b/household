import { execFileSync } from "node:child_process"
import { pathToFileURL } from "node:url"

// A folder config/importmap.rb pins whole is a directory of app/javascript.
const FOLDERS = ["channels", "controllers", "helpers", "uploader"]

// Stimulus and Turbo come from their gems, which serve them to the browser,
// so the tests load the very file the app ships rather than a copy from npm
// that could drift from it.
const GEM_PINS = {
  "@hotwired/stimulus": { gem: "stimulus-rails", file: "stimulus.min.js" },
  "@hotwired/turbo-rails": { gem: "turbo-rails", file: "turbo.min.js" }
}

const root = pathToFileURL("./app/javascript/").href

export function resolve(specifier, context, next) {
  const pin = GEM_PINS[specifier]
  if (pin) return { url: gemAsset(pin), shortCircuit: true }

  const folder = specifier.split("/")[0]
  if (FOLDERS.includes(folder) && !specifier.endsWith(".js")) {
    return { url: root + specifier + ".js", shortCircuit: true }
  }
  return next(specifier, context)
}

function gemAsset({ gem, file }) {
  const path = execFileSync("bundle", ["info", "--path", gem], { encoding: "utf8" }).trim()
  return pathToFileURL(`${path}/app/assets/javascripts/${file}`).href
}
