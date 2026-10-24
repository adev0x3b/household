# frozen_string_literal: true

# The measuring stick for lab report OCR (`bin/rails lab_reports:ocr_bench`).
#
# Each case is eval/lab_reports/ocr/<name>.yml: the rows a report shows, and
# how to draw it when there's no real screenshot next to it (<name>.png, or
# <name>-1.png, <name>-2.png… for a report in several screenshots):
#
#   rows:
#     - [Emoglobina, "13,5", g/dL, "12,0 - 16,0"]
#   render: { theme: dark, font_size: 14, pages: 2 }
#
# A row counts as read when one OCR'd line has its analyte, its value (a
# decimal comma or point alike), its unit (as Assistant::UnitName reads it —
# "10^3/uL" is "10^3/µL") and its range. Drop in anonymized real
# screenshots with their rows; a preprocessing change must not lower the
# score.
module LabReports
  class OcrBench
    DIR = Rails.root.join("eval/lab_reports/ocr")
    FONT = "DejaVu Sans"
    COLORS = { "light" => [ 255, 20 ], "dark" => [ 30, 225 ] }.freeze # [background, ink] grey levels

    Row = Data.define(:analyte, :value, :unit, :range) do
      def read_in?(text) = text.each_line.any? { |line| on?(line) }

      private

      def on?(line)
        Assistant::TextMatch.fold(line).include?(Assistant::TextMatch.fold(analyte)) &&
          numbers(line).include?(number(value)) &&
          (unit.empty? || line.split(/\s+/).any? { |token| Assistant::UnitName.key(token) == Assistant::UnitName.key(unit) }) &&
          (range.empty? || squeeze(line).include?(squeeze(range)))
      end

      def numbers(line) = line.scan(/\d+(?:[.,]\d+)?/).map { |n| number(n) }
      def number(text) = text.to_s.tr(",", ".").sub(/\.0+\z/, "")
      def squeeze(text) = text.to_s.downcase.tr(",", ".").gsub(/\s+/, "")
    end

    CaseResult = Data.define(:name, :rows, :read, :misses, :seconds, :error) do
      def score = rows.zero? ? 0.0 : read.to_f / rows
    end

    def self.cases(filter = nil)
      Dir[DIR.join("*.yml")].map { |path| File.basename(path, ".yml") }.select { |name| filter.blank? || name.include?(filter) }
    end

    def initialize(name, dir: DIR)
      @name = name
      @dir = Pathname(dir)
      spec = YAML.load_file(@dir.join("#{name}.yml"))
      @rows = spec.fetch("rows").map { |analyte, value, unit, range| Row.new(analyte.to_s, value.to_s, unit.to_s, range.to_s) }
      @render = spec.fetch("render", {}).to_h
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      text = with_pages { |paths| paths.map { |path| LabReports::Ocr.read(path) }.join("\n") }
      misses = @rows.reject { |row| row.read_in?(text) }
      CaseResult.new(name: @name, rows: @rows.size, read: @rows.size - misses.size, misses: misses,
                     seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, error: nil)
    rescue LabReports::Ocr::Error => e
      CaseResult.new(name: @name, rows: @rows.size, read: 0, misses: @rows, seconds: 0, error: e.message)
    end

    # The screenshots: real ones next to the YAML, else drawn from its rows.
    def with_pages
      real = [ @dir.join("#{@name}.png"), *Dir[@dir.join("#{@name}-*.png")].map { |p| Pathname(p) } ].select(&:exist?)
      return yield(real.map(&:to_s)) if real.any?

      Dir.mktmpdir("ocr_bench") do |tmp|
        yield(render(tmp))
      end
    end

    private

    # One PNG per page, rows split evenly, drawn like a phone screenshot:
    # columns at fixed positions, the theme's background and text colour.
    def render(tmp)
      require "vips"

      pages = @render.fetch("pages", 1).to_i.clamp(1, 5)
      size = @render.fetch("font_size", 26).to_i
      background, ink = COLORS.fetch(@render.fetch("theme", "light"))
      @rows.each_slice((@rows.size / pages.to_f).ceil).with_index(1).map do |rows, page|
        path = File.join(tmp, "#{@name}-#{page}.png")
        page_image(rows, size, background, ink).write_to_file(path)
        path
      end
    end

    # The glyphs of every cell drawn into one mask, then background and ink
    # blended through it (an RGB PNG, like a real screenshot).
    def page_image(rows, size, background, ink)
      column_x = [ 0, 16, 25, 36 ].map { |chars| chars * size * 0.62 }
      line_height = (size * 2.2).round
      width = (column_x.last + (size * 9)).round + (2 * size)
      mask = Vips::Image.black(width, (line_height * rows.size) + (size * 2))
      rows.each_with_index do |row, i|
        [ row.analyte, row.value, row.unit, row.range ].each_with_index do |cell, column|
          next if cell.empty?

          glyphs = Vips::Image.text(ERB::Util.html_escape(cell), font: "#{FONT} #{size}", dpi: 72)
          mask = mask.insert(glyphs, (size + column_x[column]).round, size + (i * line_height))
        end
      end
      page = ((mask * ((ink - background) / 255.0)) + background).cast(:uchar)
      page.bandjoin([ page, page ]).copy(interpretation: :srgb)
    end
  end
end
