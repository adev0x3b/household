# frozen_string_literal: true

require "test_helper"

# The form every record is edited in, inside its modal.
class Components::FormTest < ActiveSupport::TestCase
  class InModal < Views::Base
    def initialize(record:, form_data: {}) = (@record, @form_data = record, form_data)

    def view_template
      render Components::Modal.new do |modal|
        modal.modal_header(title: "Recipe")
        render Components::Form.new(record: @record, url: "/recipes", modal: modal, form_data: @form_data) do |f|
          f.text_field :name
        end
      end
    end
  end

  test "a new record is created and a saved one updated, each button saying which" do
    created = parse(InModal.new(record: Recipe.new))
    updated = parse(InModal.new(record: recipes(:roast_chicken)))

    assert_equal [ "post", nil ], [ created.at_css("form")["method"], created.at_css("input[name=_method]") ]
    assert_equal "patch", updated.at_css("input[name=_method]")["value"]
    assert_equal([ I18n.t("form.create"), I18n.t("form.update") ], [ created, updated ].map { _1.at_css("input[type=submit]")["value"] })
  end

  test "in a modal its submit is the footer's, always there to press, even with something missing" do
    submit = parse(InModal.new(record: Recipe.new)).at_css(".modal__footer .modal__footer-main input[type=submit]")

    assert_not submit.has_attribute?("disabled")
    assert_not submit.has_attribute?("aria-disabled")
  end

  test "a form sent back refused says what is missing from the start; a new one waits for the reader" do
    refused = Recipe.new(profile: profiles(:alice)).tap(&:validate)

    submitted = [ refused, Recipe.new ].map { parse(InModal.new(record: _1)).at_css("form")["data-modal-form-submitted-value"] }

    assert_equal [ "true", "false" ], submitted
  end

  test "a kind's own controllers join the form's, and what it didn't save says why above its fields, staying" do
    recipe = Recipe.new(profile: profiles(:alice)).tap(&:validate)
    form = parse(InModal.new(record: recipe, form_data: { controller: "recipe-form", action: "input->recipe-form#sync" })).at_css("form")

    assert_equal "modal-form typed-fields recipe-form", form["data-controller"]
    assert_includes form["data-action"], "input->recipe-form#sync"
    assert_empty form.css(".toast")
    assert_equal [ "alert", "Name can't be blank" ], [ form.at_css(".modal__body .notice")["role"], form.at_css(".modal__body .notice li").text ]
  end

  test "a form of something edited together says what was typed in it, still naming, shown again, what was typed before" do
    recipe = recipes(:roast_chicken)
    recipe.typed_fields = EditedTogether::TypedFields.new([ "recipe[name]" ], {}, under: "recipe")
    form = parse(InModal.new(record: recipe)).at_css("form")

    assert_includes form["data-action"], "submit->typed-fields#note"
    assert_equal([ "recipe[name]" ], form.css("input[type=hidden][name='typed_fields[]']").map { _1["value"] })
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
end
