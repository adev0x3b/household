# frozen_string_literal: true

module Deployment
  # A published release of the app: the GitHub repository it comes from and
  # its calendar version (2026.11.1). Its notes are the GitHub Release on
  # the version's tag.
  Release = Data.define(:repository, :version) do
    # The release an image reference names, else nil.
    def self.from_image(reference)
      match = RELEASE_IMAGE.match(reference.to_s.strip)
      match && new(repository: match[:repository], version: match[:version])
    end

    def tag = "v#{version}"
    def notes_url = "https://github.com/#{repository}/releases/tag/#{tag}"

    # Calendar versions compare part by part as numbers: 2026.11.10 comes after 2026.11.9.
    def newer_than?(other) = Gem::Version.new(version) > Gem::Version.new(other.version)
  end
end
