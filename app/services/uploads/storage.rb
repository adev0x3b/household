# frozen_string_literal: true

module Uploads
  # Where the files are: `storage/files` (on the `household_storage` volume
  # in production), each under its own key, two directory levels down so no
  # directory grows huge, readable by the app alone. Nothing is ever
  # overwritten: chunks are appended at the offset the file has reached,
  # and the append refuses if the file on disk isn't where the caller
  # thinks (Mismatch).
  module Storage
    class Mismatch < StandardError; end

    READ_SIZE = 1.megabyte
    # A file's key: a UUID (Upload), the only thing a path on disk is made of.
    KEY = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def self.root = @root || Rails.root.join("storage/files")

    # Tests point this at a directory of their own (test/support/test_file_roots.rb).
    def self.root=(path)
      @root = path && Pathname(path)
    end

    def self.path(key)
      raise ArgumentError, "not a file key: #{key.inspect}" unless KEY.match?(key.to_s)

      root.join(key[0, 2], key[2, 2], key)
    end

    # Appends what `io` holds at `at`, the file's size so far. Returns how
    # many bytes were written.
    def self.append(key, io, at:)
      file = path(key)
      FileUtils.mkdir_p(file.dirname, mode: 0o700)
      raise Mismatch, "#{key} is #{size(key)} bytes, not #{at}" unless size(key) == at

      File.open(file, "ab", 0o600) { |out| IO.copy_stream(io, out) }
    end

    def self.size(key)
      file = path(key)
      File.exist?(file) ? File.size(file) : 0
    end

    def self.exist?(key) = File.exist?(path(key))

    def self.delete(key) = FileUtils.rm_f(path(key))

    def self.sha256(key) = Digest::SHA256.file(path(key)).hexdigest

    # The content type from the first bytes, the name as a second opinion,
    # what the browser said as a last one.
    def self.content_type(key, name:, declared: nil)
      File.open(path(key), "rb") { |file| Marcel::MimeType.for(file, name: name, declared_type: declared) }
    end
  end
end
