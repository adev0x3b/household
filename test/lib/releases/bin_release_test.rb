# frozen_string_literal: true

require "test_helper"

# bin/release as the Release workflow runs it, in a checkout of its own.
class Releases::BinReleaseTest < ActiveSupport::TestCase
  include ReleaseRepositories

  DIGEST = "sha256:#{"b" * 64}"

  test "a new release prints its version, tag and previous, and writes its notes and files" do
    with_repository do |repo|
      repo.commit("Start", "compose.yml" => "image: ${HOUSEHOLD_IMAGE}\n", "install.sh" => "#!/bin/sh\n")
      Dir.mktmpdir do |out|
        output, status = release(repo, "HEAD", out)

        assert_predicate status, :success?, output
        version = output[/^version=(.+)$/, 1]
        # The script reads the machine's clock, which neither the year-ahead
        # run's moved clock nor travel_to reaches, so the version is checked
        # against the day it printed.
        on = Date.iso8601(output[/^on=(.+)$/, 1])
        assert_equal "#{on.year}.#{on.month}.1", version
        assert_includes output, "tag=v#{version}\n"
        assert_includes output, "previous=\n"
        assert_equal %w[SHA256SUMS compose.yml install.sh release.json], Dir.children(File.join(out, "assets")).sort
        assert File.executable?(File.join(out, "assets", "install.sh"))
        assert_equal "image: ghcr.io/owner/household:#{version}@#{DIGEST}\n", File.read(File.join(out, "assets", "compose.yml"))
        assert_match "## The first release", File.read(File.join(out, "notes.md"))
      end
    end
  end

  test "the day named takes the place of today's, so a release written again keeps its version" do
    with_repository do |repo|
      repo.commit("Start")
      Dir.mktmpdir do |out|
        output, status = Open3.capture2e(script, "HEAD", out, "--image", "ghcr.io/owner/household", "--digest", DIGEST,
                                         "--on", "2026-10-31", chdir: repo.root)

        assert_predicate status, :success?, output
        assert_includes output, "version=2026.10.1\n"
        assert_includes output, "on=2026-10-31\n"
      end
    end
  end

  test "a commit that makes no release prints why and writes nothing" do
    with_repository do |repo|
      repo.commit("Start")
      repo.tag("v2026.10.1")
      Dir.mktmpdir do |out|
        output, status = release(repo, "HEAD", out)

        assert_predicate status, :success?, output
        assert_match(/\Askip=\h{7} is v2026\.10\.1 already\.\n\z/, output)
        assert_empty Dir.children(out)
      end
    end
  end

  test "a digest that isn't one, or a missing argument, is refused" do
    with_repository do |repo|
      repo.commit("Start")

      output, status = Open3.capture2e(script, "HEAD", "out", "--image", "ghcr.io/owner/household", "--digest", "latest",
                                       chdir: repo.root)
      assert_equal 2, status.exitstatus, output
      _output, status = Open3.capture2e(script, "HEAD", chdir: repo.root)
      assert_equal 2, status.exitstatus
    end
  end

  private

  def script = Rails.root.join("bin/release").to_s

  def release(repo, commit, out)
    Open3.capture2e(script, commit, out, "--image", "ghcr.io/owner/household", "--digest", DIGEST, chdir: repo.root)
  end
end
