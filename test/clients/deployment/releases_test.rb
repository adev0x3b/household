# frozen_string_literal: true

require "test_helper"

# Deployment::Releases asks GitHub for a repository's newest release,
# without a token; the network is one method (perform), swapped here.
class Deployment::ReleasesTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  def answering(code, body = "")
    sent = []
    swapping(Deployment::Releases, :perform, ->(request) { sent << request; Response.new(code, body.is_a?(String) ? body : body.to_json) }) do
      @answer = Deployment::Releases.latest("adev0x3b/household")
    end
    sent
  end

  test "the newest release is its tag's version, asked of the repository's public releases" do
    sent = answering("200", { tag_name: "v2026.11.3", name: "Household 2026.11.3" })

    assert_equal Deployment::Release.new(repository: "adev0x3b/household", version: "2026.11.3"), @answer
    assert_equal "https://api.github.com/repos/adev0x3b/household/releases/latest", sent.sole.uri.to_s
    assert_nil sent.sole["Authorization"]
  end

  test "a repository that has published no release has none" do
    answering("404", { message: "Not Found" })

    assert_nil @answer
  end

  test "a tag that isn't a release's, an error and silence are the service's trouble" do
    assert_raises(Deployment::Releases::Error) { answering("200", { tag_name: "nightly" }) }
    assert_raises(Deployment::Releases::Error) { answering("403", { message: "rate limited" }) }
    swapping(Net::HTTP, :start, ->(*, **) { raise Net::OpenTimeout }) do
      error = assert_raises(Deployment::Releases::Error) { Deployment::Releases.latest("adev0x3b/household") }
      assert_match(/GitHub's releases isn't answering/, error.message)
    end
  end
end
