# frozen_string_literal: true

# One of the pages Rails serves straight from public/ when the app can't
# answer: a wrong address, a refused change, a crash, a browser too old. Each
# is a whole document with its styles inside, because nothing of the app's
# assets is sure to load with it, and it reads as the app does, in the app's
# colours (Theme). `bin/rails public:pages` writes one file per page and
# language, and test/lib/public_pages_test.rb fails when they fall behind
# this view.
class Views::PublicPages::Error < Views::Base
  # Each page by name: its status, and the name of its file under public/.
  # Rails finds a page by its status; the browser page has the name
  # ApplicationController#refuse_browser looks for.
  PAGES = {
    bad_request: [ 400, "400" ],
    not_found: [ 404, "404" ],
    not_acceptable: [ 406, "406-unsupported-browser" ],
    unprocessable: [ 422, "422" ],
    server_error: [ 500, "500" ]
  }.freeze

  # The page's own styles, in the app's colours. Font names stay unquoted
  # and the selectors simple, so the text needs no character Phlex escapes.
  STYLE = <<~CSS
    *, *::before, *::after { box-sizing: border-box; margin: 0; }
    body {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100dvh;
      padding: 1.5rem;
      background: #{Theme::PAGE};
      color: #{Theme::TEXT};
      font-family: Inter, SF Pro, Segoe UI, Roboto, Oxygen, Ubuntu, Helvetica Neue, Helvetica, Arial, sans-serif;
      line-height: 1.5;
      -webkit-font-smoothing: antialiased;
    }
    main {
      width: 100%;
      max-width: 26rem;
      padding: 2rem 1.5rem;
      border-radius: 0.75rem;
      background: #{Theme::SURFACE};
      text-align: center;
    }
    .status {
      margin-top: 1rem;
      color: #{Theme::MUTED};
      font-size: 0.8125rem;
      font-weight: 700;
      letter-spacing: 0.03em;
      text-transform: uppercase;
    }
    h1 {
      margin-top: 0.25rem;
      font-size: 1.5rem;
      font-weight: 700;
    }
    .body {
      margin-top: 0.75rem;
      color: #{Theme::MUTED};
      font-size: 0.9375rem;
    }
    .home {
      display: inline-block;
      margin-top: 1.5rem;
      padding: 0.5rem 1.25rem;
      border-radius: 0.5rem;
      background: #{Theme::ACCENT};
      color: #{Theme::PAGE};
      font-weight: 600;
      text-decoration: none;
    }
    .home:hover { background: #{Theme::ACCENT_PRESSED}; }
    .home:focus-visible { outline: 2px solid #{Theme::TEXT}; outline-offset: 2px; }
  CSS

  # The file is named as Rails looks for it (ActionDispatch::PublicExceptions):
  # "404.it.html" in Italian, and in the default language the plain "404.html",
  # which Rails serves to a reader whose language has no page.
  def self.file(name, locale)
    stem = PAGES.fetch(name).last
    locale.to_sym == I18n.default_locale ? "#{stem}.html" : "#{stem}.#{locale}.html"
  end

  # The page as its file holds it, in the language the file is for.
  def self.document(name, locale) = I18n.with_locale(locale) { new(name).call }

  def initialize(name)
    @name = name
    @status = PAGES.fetch(name).first
  end

  # The file is the same whichever environment wrote it: no development
  # marker in front of it.
  def before_template = nil

  def view_template
    doctype
    comment { "Written by bin/rails public:pages from app/views/public_pages/error.rb: change it there." }
    html(lang: I18n.locale) do
      head do
        meta(charset: "utf-8")
        title { t("navbar.title.page", page: t("public_pages.pages.#{@name}.title"), app: t("pwa.manifest.name")) }
        meta(name: "viewport", content: "width=device-width,initial-scale=1,viewport-fit=cover")
        meta(name: "robots", content: "noindex, nofollow")
        meta(name: "theme-color", content: Theme::SURFACE)
        link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
        style { STYLE }
      end
      body do
        main do
          img(src: "/icon.svg", alt: "", width: 64, height: 64)
          p(class: "status") { t("public_pages.pages.#{@name}.status", status: @status) }
          h1 { t("public_pages.pages.#{@name}.title") }
          p(class: "body") { t("public_pages.pages.#{@name}.body") }
          # The browser page offers no way back: the app would refuse the same browser again.
          a(href: "/", class: "home") { t("public_pages.home") } unless @name == :not_acceptable
        end
      end
    end
  end
end
