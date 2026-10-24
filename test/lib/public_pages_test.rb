# frozen_string_literal: true

require "test_helper"

# The error pages in public/ are files, written by `bin/rails public:pages`
# from Views::PublicPages::Error, one per language. A change to the view or
# to its words that wasn't written out fails here, naming the file.
class PublicPagesTest < ActiveSupport::TestCase
  Views::PublicPages::Error::PAGES.each_key do |name|
    I18n.available_locales.each do |locale|
      test "public/#{Views::PublicPages::Error.file(name, locale)} is the page as the view renders it" do
        file = Rails.public_path.join(Views::PublicPages::Error.file(name, locale))

        assert_path_exists file, "#{file.basename} is missing: run bin/rails public:pages"
        assert_equal Views::PublicPages::Error.document(name, locale), file.read,
                     "#{file.basename} is behind: run bin/rails public:pages"
      end
    end
  end

  test "the default language's page is the file Rails falls back to, the others carry their language" do
    assert_equal "404.html", Views::PublicPages::Error.file(:not_found, :en)
    assert_equal "404.it.html", Views::PublicPages::Error.file(:not_found, :it)
    assert_equal "406-unsupported-browser.it.html", Views::PublicPages::Error.file(:not_acceptable, :it)
  end

  test "a page is a whole document in the app's colours, in its language, with a way home" do
    page = Views::PublicPages::Error.document(:not_found, :it)

    assert page.start_with?("<!doctype html>"), "no doctype"
    assert_includes page, %(<html lang="it">)
    assert_includes page, ERB::Util.html_escape(I18n.t("public_pages.pages.not_found.title", locale: :it))
    assert_includes page, Theme::PAGE
    assert_includes page, %(href="/")
  end

  test "the unsupported-browser page points nowhere the same browser would be refused again" do
    assert_not_includes Views::PublicPages::Error.document(:not_acceptable, :en), %(href="/")
  end

  test "the file is the same whichever environment writes it" do
    assert_not_includes Views::PublicPages::Error.document(:not_found, :en), "<!-- Before"
  end
end
