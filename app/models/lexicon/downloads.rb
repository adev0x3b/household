# frozen_string_literal: true

# The extracts imports downloaded, kept so a language can be imported again
# from the same file (the admin page's "use the file already downloaded"):
# storage/lexicons/<code>.jsonl.gz, written whole or not at all
# (Lexicon::Source#each_line saves to a .part and renames it once the
# download is complete and its gzip stream whole).
#
#   Lexicon::Downloads.info("it")  # => { size: 75783172, saved_at: 2026-10-04 09:12 }, or nil
module Lexicon
  module Downloads
    DIR = Rails.root.join("storage/lexicons")

    module_function

    def dir = @dir || DIR

    # Tests point this at a temporary directory.
    def dir=(path)
      @dir = path && Pathname(path)
    end

    def path(code) = dir.join("#{code}.jsonl.gz")

    def info(code)
      file = path(code)
      { size: file.size, saved_at: file.mtime } if file.file?
    end
  end
end
