// The app's modules import each other and their libraries by the names
// config/importmap.rb pins ("helpers/csrf", "@hotwired/stimulus"), which
// Node can't resolve by itself. This registers the hook that resolves them
// the way the browser does.
import { register } from "node:module"

register("./importmap_hooks.js", import.meta.url)
