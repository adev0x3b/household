# frozen_string_literal: true

module Uploads
  # The name a file is kept and given back under: what the person called
  # it, with nothing a filesystem or a browser could trip on. Path
  # separators and control characters go, so do the leading dots, spaces and
  # dashes (a hidden file, an option), and a long name is cut keeping its
  # extension. A name with nothing left is "file"; nothing at all stays
  # nothing (the record says a name is needed).
  module Filename
    FALLBACK = "file"
    FORBIDDEN = %r{[/\\\u0000-\u001f\u007f:*?"<>|]}
    LEADING = /\A[\s.\-]+/

    def self.clean(value, max: Upload::NAME_LENGTH)
      return if value.blank?

      name = value.to_s.unicode_normalize(:nfc).gsub(FORBIDDEN, " ").squish.sub(LEADING, "")
      return FALLBACK if name.blank?
      return name if name.length <= max

      extension = File.extname(name)
      extension = "" if extension.length > 16
      name.delete_suffix(extension).first(max - extension.length).strip + extension
    end
  end
end
