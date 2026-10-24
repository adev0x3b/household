# frozen_string_literal: true

namespace :lab_reports do
  desc "Score lab report OCR on eval/lab_reports/ocr (rows read / rows); CASES=substring narrows it, SAVE=dir keeps the drawn screenshots"
  task ocr_bench: :environment do
    total = read = 0
    LabReports::OcrBench.cases(ENV["CASES"]).each do |name|
      bench = LabReports::OcrBench.new(name)
      if ENV["SAVE"].present?
        bench.with_pages { |paths| paths.each { |path| FileUtils.cp(path, File.join(ENV["SAVE"], File.basename(path))) } }
      end
      result = bench.call
      total += result.rows
      read += result.read
      puts format("  %-24s %2d/%-2d  %4.1fs%s", name, result.read, result.rows, result.seconds, result.error ? "  error: #{result.error}" : "")
      result.misses.each { |row| puts "      missed: #{row.to_h.values.join(" | ")}" }
    end
    puts format("  %-24s %2d/%-2d  (%d%%)", "TOTAL", read, total, total.zero? ? 0 : 100 * read / total)
  end
end
