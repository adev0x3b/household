# frozen_string_literal: true

require "test_helper"

# The home pages are listed once, under the key each page says is its own,
# and every report says which page it is on.
class Views::Home::PagesTest < ActiveSupport::TestCase
  test "each page is listed under its own key, and the overview is the overview" do
    assert_equal :overview, Views::Home::Pages::OVERVIEW.key
    Views::Home::Pages::SECTIONS.each do |key, page|
      assert_equal key, page.key.to_s, page.name
      assert_match(/\Afa-/, page.icon, page.name)
    end
  end

  test "a page's reports are its own, each named once" do
    Views::Home::Pages::SECTIONS.each_value do |page|
      names = page.reports.map(&:report_name)
      assert_equal names.uniq, names, page.name
      page.reports.each { |report| assert_equal page.key, report.page, report.name }
      names.each { |name| assert_equal page.report(name.to_s), page.report(name), name }
    end
  end
end
