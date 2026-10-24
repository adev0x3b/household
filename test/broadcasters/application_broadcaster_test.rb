# frozen_string_literal: true

require "test_helper"

# Every broadcaster is an ApplicationBroadcaster: one way to
# render for a viewer and to stream, and one error policy — a push that
# fails is reported, and what caused it goes on.
class ApplicationBroadcasterTest < ActiveSupport::TestCase
  test "every class in app/broadcasters is one" do
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/broadcasters").to_s)
    files = Dir[Rails.root.join("app/broadcasters/**/*.rb")].reject { _1.end_with?("application_broadcaster.rb") }
    names = files.map { _1.delete_prefix(Rails.root.join("app/broadcasters/").to_s).delete_suffix(".rb").camelize }

    assert_not_empty names
    names.each { assert_operator _1.constantize, :<, ApplicationBroadcaster, _1 }
  end

  test "a push that fails is reported, and the change it follows goes on" do
    notification = Notifications::Deliver.call(recipient: profiles(:bob), kind: :shared, subject: recipes(:roast_chicken), actor: profiles(:alice))
    broken = ->(*) { raise IOError, "the cable server went away" }

    report = assert_error_reported(IOError) do
      swapping(Turbo::StreamsChannel, :broadcast_stream_to, broken) { Notifications::Broadcaster.refreshed(notification) }
    end
    assert_equal "Notifications::Broadcaster", report.context[:broadcaster]
  end
end
