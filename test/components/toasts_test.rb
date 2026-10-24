# frozen_string_literal: true

require "test_helper"

# The layout's toasts: the flash's, and the failures the browser tells
# about, ready in the reader's language.
class Components::ToastsTest < ActiveSupport::TestCase
  test "it shows the flash's toasts and none of Devise's other flags" do
    container = parse(Components::Toasts.new(flash: { "success" => "Saved", "timedout" => true, "alert" => "Refused" }))

    assert_equal [ "Saved", "Refused" ], container.css(".toast-container > .toast .toast__message").map(&:text)
  end

  test "it is kept through a catch-up refresh and answers Turbo's failed requests" do
    container = parse(Components::Toasts.new(flash: {})).at_css("#toast-container")

    assert_equal "kept", container["data-catch-up-target"]
    assert_equal "polite", container["aria-live"], "a toast added to it is read"
    assert_equal "failed-request", container["data-controller"]
    assert_equal %w[
      turbo:fetch-request-error@document->failed-request#unanswered
      turbo:before-fetch-response@document->failed-request#answered
      turbo:frame-missing@document->failed-request#frameMissing
    ], container["data-action"].split
  end

  test "each failure is a whole alert toast in a template, in the reader's language" do
    container = I18n.with_locale(:it) { parse(Components::Toasts.new(flash: {})) }

    toasts = %w[offline serverError missing].to_h do |target|
      template = container.at_css("template[data-failed-request-target=#{target}]")
      [ target, template.at_css(".toast.toast--alert .toast__message").text ]
    end

    assert_equal({ "offline" => I18n.t("failures.offline", locale: :it),
                   "serverError" => I18n.t("failures.server_error", locale: :it),
                   "missing" => I18n.t("failures.missing", locale: :it) }, toasts)
    assert_empty container.css(".toast-container > .toast"), "a failure shows only when it happens"
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call)
end
