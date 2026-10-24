# frozen_string_literal: true

require "open3"

# Extracts text from a photo of a lab report so the assistant can read it
# like any other typed message (see "Photos of lab reports" in
# docs/architecture/assistant.md).
#
# Preprocessing (grayscale, dark mode inverted, scaled to a fixed text line
# height, percentile contrast stretch, sharpen, threshold) took Tesseract from two silently-wrong digits and dropped
# decimal commas to a perfect read on a real report — plain OCR on the raw
# screenshot is measurably worse, vision models tested at the time were both
# slower and less accurate. Shells out to the system `tesseract` binary
# (added to the Docker image's base stage) under a hard timeout.
#
#   text = LabReports::Ocr.call(attachment: message.attachments.first)
#   text = LabReports::Ocr.read("screenshot.png")   # a file (the OCR bench)
#
# Measured by `bin/rails lab_reports:ocr_bench` (eval/lab_reports/ocr/): a
# preprocessing change must not lower its score.
module LabReports
  class Ocr
    # The copy can't read photos at all: a program it needs is missing or
    # fails. Whoever runs the app has to fix it.
    class Error < StandardError; end

    # This photo has no text the app could find, which is the photo's
    # problem, not the app's.
    class Unreadable < Error; end

    TEXT_HEIGHT = 60 # px a line of text is scaled to (measured, see #scale_for)
    SCALE_LIMITS = (1.0..6.0)
    FALLBACK_SCALE = 2.5 # when no text lines can be measured
    THRESHOLD = 150
    CONTRAST_PERCENTILE = 1 # clip the darkest/lightest 1% before stretching
    TIMEOUT_SECONDS = 20
    MAX_LINES = 80
    DEFAULT_LANGUAGES = "ita+eng"

    def self.call(attachment:) = new(attachment).call

    def self.read(path) = new(nil).read(path)

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      Tempfile.create([ "lab_report_src", source_extension ], binmode: true) do |src|
        src.write(@attachment.download)
        src.flush
        read(src.path)
      end
    end

    def read(path)
      Tempfile.create([ "lab_report_pre", ".png" ]) do |pre|
        preprocess(path, pre.path)
        text = run_tesseract(pre.path)
        raise Unreadable, "no text extracted" if text.blank?

        clean(text)
      end
    end

    private

    def source_extension
      File.extname(@attachment.filename.to_s).presence || ".jpg"
    end

    def preprocess(in_path, out_path)
      require "vips"

      image = Vips::Image.new_from_file(in_path).colourspace("b-w")
      image = image.extract_band(0) if image.bands > 1 # the b-w alpha of a PNG screenshot
      image = image.invert if image.avg < 128 # dark mode: light text on a dark background
      image = image.resize(scale_for(image), kernel: :lanczos3)
      low = image.percent(CONTRAST_PERCENTILE)
      high = image.percent(100 - CONTRAST_PERCENTILE)
      image = ((image - low) * (255.0 / (high - low))).cast(:uchar)
      image = image.sharpen
      image = (image > THRESHOLD).ifthenelse(255, 0)
      image.write_to_file(out_path)
    rescue LoadError => e
      raise Error, "libvips is not installed: #{e.message}"
    rescue Vips::Error
      # Vips names the temporary file in its message, so its error is kept as
      # the cause and the report is one kind, whichever photo it was.
      raise Error, "libvips couldn't prepare the photo"
    end

    # Scale so a line of text is TEXT_HEIGHT px tall, whatever the
    # screenshot's resolution: a small crop is enlarged more, a full-size
    # phone screenshot less. Line height = the median run of rows holding
    # ink (dark pixels, after the dark-mode inversion).
    def scale_for(image)
      ink_rows = (image < 128).project[1].to_a.flatten.map { |count| count.positive? }
      runs = ink_rows.chunk_while { |a, b| a == b }.filter_map { |run| run.size if run.first && run.size > 2 }
      return FALLBACK_SCALE if runs.empty?

      (TEXT_HEIGHT / runs.sort[runs.size / 2].to_f).clamp(SCALE_LIMITS)
    end

    def run_tesseract(path)
      languages = ENV.fetch("OCR_LANGUAGES", DEFAULT_LANGUAGES)
      command = [ "timeout", "-k", "5", TIMEOUT_SECONDS.to_s, "tesseract", path, "-", "-l", languages, "--psm", "6" ]
      stdout, stderr, status = Open3.capture3(*command)
      raise Error, "tesseract failed: #{stderr.presence || status}" unless status.success?

      stdout
    rescue Errno::ENOENT => e
      raise Error, "tesseract is not installed: #{e.message}"
    end

    def clean(text)
      text.each_line.map(&:strip).reject(&:blank?).first(MAX_LINES).join("\n")
    end
  end
end
