# frozen_string_literal: true

require "test_helper"

class Deployment::HealthTest < ActiveSupport::TestCase
  isolate_env "KAMAL_DESTINATION"

  test "a destination's address is its host under the mount path; none without a host" do
    assert_equal "https://staging.household.example#{Rails.configuration.x.mount_path}", Deployment.url("staging")

    ENV.delete("PRODUCTION_HOST")
    assert_nil Deployment.url("production")
    assert_instance_of Deployment::Health::Unknown, Deployment::Health.of("production"), "nothing to ask without an address"
  end

  test "this copy checks its own database and worker" do
    ENV["KAMAL_DESTINATION"] = "staging"
    state = Deployment::Health.of(:staging)

    assert_instance_of Deployment::Health::Here, state
    assert state.database
    assert_nil state.worker, "no worker is checked in tests, and that doesn't count against it"
    assert_predicate state, :ok?
    assert_equal "here_ok", state.key

    down = Deployment::Health::Here.new(database: true, worker: false)
    assert_not down.ok?
    assert_equal "here_down", down.key
  end

  test "production is asked publicly from elsewhere; staging and dev sit behind Access, so nothing is known" do
    asked = []
    swapping(Deployment::Health, :reachable?, ->(url) { asked << url; true }) do
      state = Deployment::Health.of("production")
      assert_instance_of Deployment::Health::Public, state
      assert_predicate state, :ok?
      assert_equal "public_ok", state.key
      assert_equal [ "https://household.example#{Rails.configuration.x.mount_path}/up" ], asked

      state = Deployment::Health.of("staging")
      assert_instance_of Deployment::Health::Unknown, state
      assert_nil state.ok?
      assert_equal "unknown", state.key

      assert_instance_of Deployment::Health::Unknown, Deployment::Health.of("dev")
      assert_equal [ "https://household.example#{Rails.configuration.x.mount_path}/up" ], asked
    end
  end

  test "a public check that fails is a destination down, not an error" do
    swapping(Deployment::Health, :reachable?, ->(_url) { false }) do
      state = Deployment::Health.of("production")
      assert_equal false, state.ok?
      assert_equal "public_down", state.key
    end

    refused = ->(_request, **) { raise Deployment::Health::Error, "The health check isn't answering" }
    swapping(ApplicationClient, :perform, refused) { assert_equal false, Deployment::Health.reachable?("https://household.example/up") }
  end
end
