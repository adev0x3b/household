# frozen_string_literal: true

# The pipeline the console's tests drive: GitHub answered from the fixture
# files (GithubFixtures), production's public health check answering, and
# the deploy token the frames and the presses need.
module CannedPipeline
  SHA = "0123456789abcdef0123456789abcdef01234567"

  # GitHub answered from the fixtures, frozen or not, and production's
  # public health check answering (or not).
  def canned(up: true, frozen: false, &)
    swapping(Delivery::Github, :perform, ->(request) { GithubFixtures.perform(request, frozen: frozen) }) do
      swapping(Deployment::Health, :reachable?, ->(_url) { up }, &)
    end
  end

  # The test case isolates DEPLOY_DISPATCH_TOKEN, so the token lasts the test.
  def with_deploy_token
    ENV["DEPLOY_DISPATCH_TOKEN"] = "tok"
  end

  def workflow_run(status:, conclusion: nil, created_at: 10.minutes.ago, number: 7)
    Delivery::Github::Run.new(id: number, number: number, title: "Deploy ##{number}", event: "workflow_dispatch", status: status,
                              conclusion: conclusion, actor: "alice", created_at: created_at, updated_at: created_at, head_sha: SHA, head_branch: "main",
                              workflow: "deploy.yml", html_url: "https://github.com/example/household/actions/runs/#{number}")
  end
end
