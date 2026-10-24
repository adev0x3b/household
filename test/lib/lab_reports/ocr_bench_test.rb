# frozen_string_literal: true

require "test_helper"

# How the OCR bench scores a row, and that it can draw a case. (Its score
# depends on the installed Tesseract, so no test pins it: run
# `bin/rails lab_reports:ocr_bench`.)
class LabReports::OcrBenchTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "case.yml"), { "rows" => [ [ "Globuli bianchi", "6,8", "10^3/uL", "4,0 - 10,0" ] ] }.to_yaml)
    @bench = LabReports::OcrBench.new("case", dir: @dir)
    @row = LabReports::OcrBench::Row.new("Globuli bianchi", "6,8", "10^3/uL", "4,0 - 10,0")
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "a row is read when one line has its analyte, value, unit and range" do
    assert @row.read_in?("Globuli bianchi 6.8 K/µL 4.0-10.0\n")
    assert_not @row.read_in?("Globuli bianchi 6.88 10^3/uL 4,0 - 10,0\n"), "a wrong digit"
    assert_not @row.read_in?("Globuli bianchi 6,8 10^3/uL\n4,0 - 10,0\n"), "the range on another line"
    assert_not @row.read_in?("Globuli bianchi 6,8 10^6/uL 4,0 - 10,0\n"), "another unit"
  end

  test "a case without a real screenshot is drawn from its rows" do
    skip "libvips is not installed" unless vips_available?

    @bench.with_pages do |paths|
      assert_equal 1, paths.size
      assert_predicate Vips::Image.new_from_file(paths.first).width, :positive?
    end
  end

  private

  def vips_available?
    require "vips"
    true
  rescue LoadError
    false
  end
end
