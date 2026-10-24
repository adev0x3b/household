# frozen_string_literal: true

require "test_helper"

class Views::Shares::WhoseTest < ActiveSupport::TestCase
  test "its owner reads who else has it" do
    line = whose(recipes(:roast_chicken), viewer: profiles(:alice))

    assert_includes line.at_css("i").classes, "fa-user-group"
    assert_equal I18n.t("shares.shared_with_names", names: profiles(:bob).display_name), line.text
  end

  test "a housemate reads whose it is" do
    line = whose(recipes(:roast_chicken), viewer: profiles(:bob))

    assert_includes line.at_css("i").classes, "fa-user"
    assert_equal I18n.t("shares.owner", name: profiles(:alice).display_name), line.text
  end

  test "nothing is said while its owner keeps it to themselves" do
    assert_nil whose(recipes(:pancakes), viewer: profiles(:bob))
  end

  private

  def whose(thing, viewer:)
    Nokogiri::HTML5.fragment(Views::Shares::Whose.new(thing: thing, viewer: viewer).call).at_css("p.share-whose")
  end
end
