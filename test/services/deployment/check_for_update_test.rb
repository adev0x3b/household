# frozen_string_literal: true

require "test_helper"

# Deployment::CheckForUpdate keeps GitHub's answer for the console and
# tells the admins, once a release, when one newer than theirs is out.
class Deployment::CheckForUpdateTest < ActiveSupport::TestCase
  RUNNING = Deployment::Release.new(repository: "adev0x3b/household", version: "2026.11.2")

  setup do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  def newest_is(version, &)
    swapping(Deployment::Releases, :latest, ->(repository) { version && Deployment::Release.new(repository: repository, version: version) }, &)
  end

  test "a newer release is kept for the console and told to every admin once" do
    update = nil
    newest_is("2026.11.3") do
      assert_difference(-> { Notification.release_available.count }, 1) { update = Deployment::CheckForUpdate.call(RUNNING) }
      assert_no_difference(-> { Notification.count }) { Deployment::CheckForUpdate.call(RUNNING) }
    end

    assert_predicate update, :available?
    assert_equal "2026.11.3", update.newest.version
    notification = @admin.notifications.release_available.sole
    assert_equal "2026.11.3", notification.data["version"]
    assert_equal "Household 2026.11.3 is out", Notifications::Wording.new(notification).title
    assert_equal Rails.application.routes.url_helpers.admin_deployment_path, Notifications::Destination.new(notification).path
    assert_equal "2026.11.3", Deployment::Update.for(RUNNING).newest.version

    newest_is("2026.11.4") do
      assert_difference(-> { @admin.notifications.release_available.count }, 1) { Deployment::CheckForUpdate.call(RUNNING) }
    end
  end

  test "the release running, or none published yet, tells nobody and is still remembered" do
    newest_is("2026.11.2") do
      assert_no_difference(-> { Notification.count }) { assert_not Deployment::CheckForUpdate.call(RUNNING).available? }
    end
    newest_is(nil) do
      assert_no_difference(-> { Notification.count }) { assert_nil Deployment::CheckForUpdate.call(RUNNING).newest }
    end
    assert_in_delta Time.current, Deployment::Update.for(RUNNING).checked_at, 1.second
  end

  test "members are never told" do
    newest_is("2026.11.3") { Deployment::CheckForUpdate.call(RUNNING) }

    assert_equal [ @admin ], Notification.release_available.map(&:profile)
  end
end
