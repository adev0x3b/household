# frozen_string_literal: true

require "test_helper"

# A toast is text: whatever it names — a housemate, an item on a shared
# list — is escaped. Only markup a helper built (a SafeBuffer) is markup.
class Components::ToastTest < ActiveSupport::TestCase
  PAYLOAD = "<img src=x onerror=alert(1)>"

  test "its message and its second line are escaped" do
    html = Components::Toast.new(kind: :success, body: "Removed #{PAYLOAD}", detail: "<b>soon</b>").call

    assert_not_includes html, "<img"
    assert_includes html, "Removed &lt;img src=x onerror=alert(1)&gt;"
    assert_includes html, %(<div class="toast__detail">&lt;b&gt;soon&lt;/b&gt;</div>)
  end

  test "a <br> in the text stays text; a second line is only ever the detail" do
    html = Components::Toast.new(kind: :notice, body: "one<br>two").call

    assert_includes html, "one&lt;br&gt;two"
    assert_not_includes html, "toast__detail"
  end

  test "a link a helper built goes through as a link" do
    link = ActionController::Base.helpers.link_to("On GitHub", "https://example.com/runs/1", target: "_blank", rel: "noopener noreferrer")
    html = Components::Toast.new(kind: :success, body: "Deploying", detail: link).call

    assert_match %r{<div class="toast__detail"><a [^>]*href="https://example.com/runs/1"[^>]*>On GitHub</a></div>}, html
  end

  test "its kind is one of three, and any other is a mistake rather than a neutral toast" do
    assert_includes Components::Toast.new(kind: :alert, body: "Refused").call, "toast--alert"
    assert_raises(ArgumentError) { Components::Toast.new(kind: :error, body: "Refused") }
  end

  test "the layout draws only the flash's toasts, not the other flags Devise keeps there" do
    assert Components::Toast.kind?("notice")
    assert_not Components::Toast.kind?("timedout")
  end

  test "an alert is read at once and stays until closed; the others go by themselves" do
    alert = Nokogiri::HTML5.fragment(Components::Toast.new(kind: :alert, body: "Refused").call).at_css(".toast")
    done = Nokogiri::HTML5.fragment(Components::Toast.new(kind: :success, body: "Saved").call).at_css(".toast")

    assert_equal "alert", alert["role"]
    assert alert.key?("data-toast-until-closed-value")
    assert_nil alert.at_css("progress"), "a toast that stays has no time left to show"

    assert_nil done["role"], "its container's polite region reads it"
    assert_not done.key?("data-toast-until-closed-value")
    assert_equal "true", done.at_css("progress")["aria-hidden"]
  end

  test "it waits while the focus is in it, as it does under the pointer" do
    toast = Nokogiri::HTML5.fragment(Components::Toast.new(kind: :notice, body: "Held").call).at_css(".toast")
    actions = toast["data-action"].split

    assert_includes actions, "focusin->toast#pauseTimer"
    assert_includes actions, "focusout->toast#resumeTimer"
  end
end
