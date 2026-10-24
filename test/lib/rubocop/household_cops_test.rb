# frozen_string_literal: true

require "test_helper"
require "rubocop"
require Rails.root.join("lib/rubocop/cop/household/send_to_private").to_s
require Rails.root.join("lib/rubocop/cop/household/html_safe").to_s
require Rails.root.join("lib/rubocop/cop/household/redirect_after_write").to_s
require Rails.root.join("lib/rubocop/cop/household/aria_attributes").to_s
require Rails.root.join("lib/rubocop/cop/household/component_names_no_view").to_s
require Rails.root.join("lib/rubocop/cop/household/log_only_rescue").to_s

# The conventions RuboCop holds the code to, each cop on what it
# flags and what it lets be.
class HouseholdCopsTest < ActiveSupport::TestCase
  test "SendToPrivate flags a send into another object, never one's own dispatch" do
    cop = RuboCop::Cop::Household::SendToPrivate

    assert_equal 1, offenses(cop, "resolver.send(:dates_in, text)").size
    assert_equal 1, offenses(cop, "record&.__send__(:secret)").size
    assert_equal 1, offenses(cop, 'turbo_stream.send(:append, "modals", view)').size
    assert_empty offenses(cop, 'send(:"check_#{kind}", spec)')
    assert_empty offenses(cop, "self.send(:helper)")
    assert_empty offenses(cop, "turbo_stream.public_send(:append, view)")
  end

  test "HtmlSafe flags a string marked safe and raw output, not another object's raw" do
    cop = RuboCop::Cop::Household::HtmlSafe

    assert_equal 1, offenses(cop, '"<b>#{name}</b>".html_safe').size
    assert_equal 1, offenses(cop, 'raw(t("notices.shared", name: name))').size
    assert_equal 1, offenses(cop, "unsafe_raw(markup)").size
    assert_empty offenses(cop, 'Response.raw("migration_held.rb")')
    assert_empty offenses(cop, "plain t(\"notices.shared\")")
  end

  test "RedirectAfterWrite wants a 303 from create, update and destroy" do
    cop = RuboCop::Cop::Household::RedirectAfterWrite

    assert_equal 1, offenses(cop, "def update\n  redirect_to links_path\nend").size
    assert_equal 1, offenses(cop, "def destroy\n  redirect_back fallback_location: root_path\nend").size
    assert_empty offenses(cop, "def create\n  redirect_to links_path, status: :see_other\nend")
    assert_empty offenses(cop, "def latest\n  redirect_to chats_path\nend")
  end

  test "AriaAttributes wants ARIA in an aria: hash, and a state as the word" do
    cop = RuboCop::Cop::Household::AriaAttributes

    assert_equal 1, offenses(cop, 'button(aria_label: "Close")').size
    assert_equal 1, offenses(cop, 'form_with(url: "/r") { |f| f.submit "Save", aria_disabled: "true" }').size
    assert_equal 1, offenses(cop, 'i(class: "fa-solid fa-pen", aria: { hidden: true })').size
    assert_equal 1, offenses(cop, "button(aria: { expanded: false })").size
    assert_equal 1, offenses(cop, 'tag(:span, "…", "aria-hidden" => true)').size
    assert_empty offenses(cop, 'tag(:span, "…", "aria-hidden" => "true")')
    assert_empty offenses(cop, 'button(aria: { label: "Close", expanded: "false" })')
    assert_empty offenses(cop, 'form_with(url: "/r") { |f| f.submit "Save", aria: { disabled: "true" } }')
    assert_empty offenses(cop, "a(data: { turbo_stream: true }, hidden: true)")
  end

  test "ComponentNamesNoView flags a view named in a component, once for the whole name" do
    cop = RuboCop::Cop::Household::ComponentNamesNoView

    named = offenses(cop, "render Views::Tasks::PriorityBadge.new(priority: priority)").map { _1.location.source }
    assert_equal [ "Views::Tasks::PriorityBadge" ], named
    assert_equal 1, offenses(cop, "::Views::Home::Pages::SECTIONS.each_key { |key| key }").size
    assert_empty offenses(cop, "render Components::StatusBadge.new(tone: :good, label: label)")
    assert_empty offenses(cop, "Calendar::Views.count")
    assert_empty offenses(cop, "# Drawn by Views::Books::Show.\nrender Components::Card.new")
  end

  test "LogOnlyRescue flags a rescue that only logs, not one that reports, raises or answers" do
    cop = RuboCop::Cop::Household::LogOnlyRescue

    assert_equal 1, offenses(cop, "begin\n  lookup\nrescue Error => e\n  Rails.logger.warn(e.message)\n  nil\nend").size
    assert_equal 1, offenses(cop, "def read\n  ocr\nrescue Error => e\n  logger.error(e.message)\nend").size
    assert_empty offenses(cop, "begin\n  lookup\nrescue Error => e\n  Rails.logger.warn(e.message)\n  Rails.error.report(e, handled: true)\nend")
    assert_empty offenses(cop, "begin\n  lookup\nrescue Error => e\n  Rails.logger.error(e.message)\n  raise\nend")
    assert_empty offenses(cop, "begin\n  Date.parse(text)\nrescue Date::Error\n  nil\nend")
    assert_empty offenses(cop, "begin\n  save!\nrescue ActiveRecord::RecordInvalid\n  refuse(t(\"notices.invalid\"))\nend")
  end

  private

  def offenses(cop_class, source)
    config = RuboCop::Config.new({ cop_class.cop_name => { "Enabled" => true } }, "#{Rails.root}/.rubocop.yml")
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "#{Rails.root}/app/views/probe.rb")
    RuboCop::Cop::Commissioner.new([ cop_class.new(config) ]).investigate(processed).offenses
  end
end
