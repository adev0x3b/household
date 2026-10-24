# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# The barcode scanner's zxing-wasm binary (vendor/assets/wasm): Propshaft takes
# an asset's type from here, and WebAssembly.instantiateStreaming needs it exact.
Mime::Type.register "application/wasm", :wasm
