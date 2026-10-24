# frozen_string_literal: true

require "digest"
require "json"

module Releases
  # The files a release carries, which a copy of one's own is installed and
  # updated from: what the release is (release.json), the Compose file
  # pinned to its image, the installer, and the checksums of the others.
  class Assets
    # Where compose.yml names the app's image; the release writes the image
    # it pinned in its place.
    IMAGE_PLACEHOLDER = "${HOUSEHOLD_IMAGE}"

    def initialize(repository, plan, image:, downtime_seconds: nil)
      @plan = plan
      @image = image
      @downtime_seconds = downtime_seconds
      @compose = pinned(repository.file(plan.commit, "compose.yml"))
      @installer = repository.file(plan.commit, "install.sh")
    end

    # { name => content }, the checksums last.
    def files
      files = { "release.json" => JSON.pretty_generate(manifest) + "\n" }
      files["compose.yml"] = @compose if @compose
      files["install.sh"] = @installer if @installer
      sums = files.sort.map { |name, content| "#{Digest::SHA256.hexdigest(content)}  #{name}\n" }
      files.merge("SHA256SUMS" => sums.join)
    end

    # What a release left out because the commit didn't have it ready.
    def missing
      [ ("compose.yml names no #{IMAGE_PLACEHOLDER}, so the release carries no Compose file." unless @compose),
        ("There's no install.sh, so the release carries no installer." unless @installer) ].compact
    end

    def manifest
      {
        version: @plan.version.to_s,
        tag: @plan.version.tag,
        commit: @plan.commit,
        image: @image,
        previous: @plan.previous&.to_s,
        stopped_migrations: @plan.stopped_migrations,
        downtime_seconds: @downtime_seconds
      }
    end

    private

    def pinned(compose)
      return unless compose&.include?(IMAGE_PLACEHOLDER)

      compose.gsub(IMAGE_PLACEHOLDER, @image)
    end
  end
end
