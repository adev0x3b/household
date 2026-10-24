# frozen_string_literal: true

require "test_helper"

# Chart.js (config/importmap.rb) is fetched only when a chart connects, and
# its vendored file is the package bundled into one module, so it imports
# nothing the importmap doesn't pin.
class VendoredChartJsTest < ActiveSupport::TestCase
  test "Chart.js is pinned but no page preloads it" do
    importmap = Rails.application.importmap
    preloaded = importmap.preloaded_module_packages(resolver: ActionController::Base.helpers).values.map(&:name)

    assert_includes importmap.packages.keys, "chart.js"
    assert_not_includes preloaded, "chart.js"
    assert_not_includes preloaded, "@kurkle/color"
  end

  test "the vendored Chart.js imports only its colour library, by the pinned name" do
    source = Rails.root.join("vendor/javascript/chart.js.js").read

    assert_equal [ "@kurkle/color" ], source.scan(/\b(?:from|import)\s*"([^"]+)"/).flatten.uniq
    assert_includes Rails.application.importmap.packages.keys, "@kurkle/color"
  end
end
