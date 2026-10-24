# frozen_string_literal: true

require "test_helper"

# Every kind of thing that can be shared is wired the same way:
# a share model that shares it back, a place in SharesController, a route,
# and its modal's words in every language.
class ShareableTest < ActiveSupport::TestCase
  setup { Rails.application.eager_load! }

  def shareables = ApplicationRecord.descendants.select { _1.include?(Shareable) && _1 == _1.base_class }

  test "each has a share model that shares it back" do
    shareables.each do |klass|
      share = klass.share_class
      assert_includes share, Share, "#{share} includes Share"
      assert_equal klass, share.reflect_on_association(share.thing_name).klass, "#{share} shares #{klass}"
    end
  end

  test "each is one SharesController knows, and none it doesn't" do
    assert_equal SharesController::THINGS.sort, shareables.map(&:name).sort
  end

  test "each has the share routes and its modal's words" do
    routes = Rails.application.routes.routes.select { _1.defaults[:controller] == "shares" }.map { _1.defaults[:shareable] }.uniq
    assert_equal SharesController::THINGS.sort, routes.sort

    shareables.each do |klass|
      I18n.available_locales.each do |locale|
        %w[title subtitle].each do |part|
          assert I18n.exists?("shares.things.#{klass.model_name.i18n_key}.#{part}", locale), "#{locale}: shares.things.#{klass.model_name.i18n_key}.#{part}"
        end
      end
    end
  end

  test "who has access is its owner, then everyone it is shared with" do
    assert_equal [ profiles(:alice), profiles(:bob) ], grocery_lists(:weekly_shop).people_with_access
    assert_equal [ profiles(:bob) ], grocery_lists(:dinner_party).people_with_access
  end
end
