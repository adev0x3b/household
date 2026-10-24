# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/channels", under: "channels"
pin_all_from "app/javascript/helpers", under: "helpers"
pin_all_from "app/javascript/uploader", under: "uploader"
pin "@rails/actioncable", to: "actioncable.esm.js"
# Chart.js draws only the home pages' statistics, yet would be half of the
# JavaScript every page downloads: chart_controller.js imports it when a
# chart first connects, so no page preloads it. The vendored file is the
# package's two modules bundled into one and minified (the command is at its
# top); @kurkle/color keeps its own pin, so the importmap audit still sees it.
pin "chart.js", preload: false # @4.5.1
pin "@kurkle/color", to: "@kurkle--color.js", preload: false # @0.3.4
pin "pwa"
# The barcode scanner (barcode_scanner_controller.js, bookshelf): a ponyfill
# of the browser's BarcodeDetector over zxing-wasm, vendored from jsDelivr
# (dist/es of barcode-detector), because jspm's build only pointed at its own
# split chunks. Its one chunk is re-pinned as a bare specifier: Propshaft
# serves only digested paths, so the relative import it shipped with would
# not resolve. Loaded with a dynamic import() when the scanner opens, so
# preload: false keeps ~60 KB off every page. The wasm it runs is
# vendor/assets/wasm/zxing_reader.wasm (zxing-wasm 3.1.6, served by
# Propshaft); test/lib/vendored_wasm_test.rb keeps the two versions together.
pin "barcode-detector/ponyfill", to: "barcode-detector--ponyfill.js", preload: false # @3.2.3
pin "barcode-detector/zxing-exported", to: "barcode-detector--zxing-exported.js", preload: false # @3.2.3
