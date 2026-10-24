# frozen_string_literal: true

# What this copy of the app knows about itself. None of it asks GitHub, so
# the console can say it even when GitHub can't be reached.
module Deployment
  # Where the Deploy workflow puts a version (docs/architecture/delivery.md): dev runs
  # a branch under test; staging, the public demo and production main's commits.
  DESTINATIONS = %w[production staging demo dev].freeze
  # The ones fed from main, in the order a version travels: staging on its
  # own, the demo right after it, production by a press.
  MAINLINE = %w[staging demo production].freeze
  # A commit, as Kamal tags an image: <sha>, or <sha>_uncommitted_<hash> from a dirty checkout.
  COMMIT = /\A\h{7,40}(_uncommitted_\h+)?\z/
  # The image a release's compose.yml pins: ghcr.io/<owner>/household:<version>@sha256:<digest>,
  # the version a calendar one (2026.11.1).
  RELEASE_IMAGE = %r{\A
    ghcr\.io/(?<repository>[a-z0-9._-]+/household)
    :(?<version>\d{4}\.(?:[1-9]|1[0-2])\.[1-9]\d*)
    @sha256:\h{64}
  \z}x
  # How a self-hosted copy is updated: the installer's command, on its machine.
  UPDATE_COMMAND = "household update"

  module_function

  # The GitHub repository the pipeline runs in ("owner/name"): its Deploy
  # workflow, its freeze and its Deployments. GITHUB_REPOSITORY, which Actions
  # sets and config/deploy.yml hands to every container. A stand-in outside a
  # deployed copy (development's canned pipeline, the tests).
  def repository = ENV["GITHUB_REPOSITORY"].presence || "example/household"

  # The repository the code lives in: its commits, branches, pull requests,
  # CI and releases. SOURCE_REPOSITORY when the pipeline runs from a private
  # repository of its own (docs/architecture/delivery.md), else the pipeline's.
  def source_repository = ENV["SOURCE_REPOSITORY"].presence || repository

  # Both, once each: what the deploy token has to reach.
  def repositories = [ source_repository, repository ].uniq

  # A page of the code's repository on GitHub, github_url("commit", sha), or
  # of the pipeline's.
  def github_url(*path, repository: source_repository) = [ "https://github.com", repository, *path ].join("/")

  # A destination's public address: its <DESTINATION>_HOST under the app's
  # mount path. config/deploy.yml hands every copy every destination's host,
  # so the console can link each; nil where one isn't configured.
  def url(destination)
    host = ENV["#{destination.to_s.upcase}_HOST"].presence
    host && "https://#{host}#{Rails.configuration.x.mount_path}"
  end

  # The commit the image was built from: APP_VERSION, which CI passes to the
  # build, else the tag Kamal runs when that tag is a commit. Nil in
  # development, which runs no image.
  def version = ENV["APP_VERSION"].presence || ENV["KAMAL_VERSION"].to_s[COMMIT]
  def versioned? = version.present?

  # One of DESTINATIONS; nil outside Kamal, as in development, which no workflow deploys.
  def destination = ENV["KAMAL_DESTINATION"].presence_in(DESTINATIONS)
  def deployed? = destination.present?

  # A copy someone runs on a machine of their own, started from a release's
  # compose.yml, which hands it the image it runs (HOUSEHOLD_IMAGE). It has
  # no destination and no pipeline: its console shows this copy alone.
  def self_hosted? = !deployed? && ENV["HOUSEHOLD_IMAGE"].present?

  # The pipeline's own copies, and a development machine trying its console.
  def pipeline? = !self_hosted?

  # The release a self-hosted copy runs, read from the image it was handed;
  # nil when it runs something else, and on the pipeline's copies, which
  # Kamal runs by commit.
  def release = (Release.from_image(ENV["HOUSEHOLD_IMAGE"]) if self_hosted?)

  # The commit alone, without a dirty checkout's _uncommitted_<hash>.
  def sha = version&.split("_")&.first
  def short_version = sha&.first(7)
  def uncommitted? = version.to_s.include?("_uncommitted")
  def commit_url = (sha && github_url("commit", sha))

  def booted_at = Rails.application.config.x.deployment.booted_at

  def database_ok?
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") == 1 }
  rescue ActiveRecord::ActiveRecordError, PG::Error
    false
  end

  # Lexicon::Worker already looks for a live Solid Queue worker, and every
  # job needs the same one. Nil where jobs don't go through Solid Queue, as
  # in tests.
  def worker_alive? = Lexicon::Worker.alive?
end
