# frozen_string_literal: true

require "test_helper"

# The barcode scanner's two vendored halves (config/importmap.rb): the
# barcode-detector chunk names the zxing-wasm binary it was built for by
# its SHA-256, so an upgrade of one without the other fails here.
class VendoredWasmTest < ActiveSupport::TestCase
  test "vendor/assets/wasm/zxing_reader.wasm is the one barcode-detector expects" do
    chunk = Rails.root.join("vendor/javascript/barcode-detector--zxing-exported.js").read
    digest = Digest::SHA256.file(Rails.root.join("vendor/assets/wasm/zxing_reader.wasm")).hexdigest

    assert_includes chunk.scan(/\b[0-9a-f]{64}\b/), digest
    assert_includes chunk, "zxing-wasm@"
  end

  test "the ponyfill imports its chunk by the pinned specifier, never a relative path" do
    ponyfill = Rails.root.join("vendor/javascript/barcode-detector--ponyfill.js").read

    assert_includes ponyfill, 'from "barcode-detector/zxing-exported"'
    assert_not_includes ponyfill, 'from "./'
    assert_match %r{\A/assets/zxing_reader-\h{8}\.wasm\z}, ActionController::Base.helpers.asset_path("zxing_reader.wasm")
    assert_equal "application/wasm", Mime::Type.lookup_by_extension("wasm").to_s
  end
end
