# frozen_string_literal: true

require "test_helper"

# A modal is a header, a body that scrolls and a footer that always shows.
# Its form, when the footer submits, comes from the modal (modal_form), so
# the dialog's height reaches the body; test/support/modal_structure.rb
# checks every modal the suite renders for it.
class Components::ModalTest < ActiveSupport::TestCase
  class Sample < Views::Base
    include Phlex::Rails::Helpers::FormWith

    def initialize(wrapper:, data: {})
      @wrapper = wrapper
      @data = data
    end

    def view_template
      render Components::Modal.new do |modal|
        modal.modal_header(title: "Sample")
        if @wrapper == :modal_form
          modal.modal_form(url: "/samples", scope: :sample, class: "sample-form", data: @data) { |f| parts(modal, f) }
        else
          form_with(url: "/samples", scope: :sample, class: "sample-form") { |f| parts(modal, f) }
        end
      end
    end

    private

    def parts(modal, f)
      modal.modal_body { f.text_field :name }
      modal.modal_footer { f.submit "Save", class: "modal__btn modal__btn--primary" }
    end
  end

  test "modal_form wraps the body and the footer in the form that hands down the dialog's height" do
    html = render(:modal_form)

    form = Nokogiri::HTML5.fragment(html).at_css(".modal__dialog > form")
    assert_equal %w[modal__form sample-form], form.classes
    assert_equal "/samples", form["action"]
    assert_equal "_top", form["data-turbo-frame"]
    assert form.at_css("> .modal__body input[name='sample[name]']")
    assert form.at_css("> .modal__footer .modal__btn--cancel + input[type=submit]")
    assert_empty ModalStructure.problems(html)
  end

  test "its form leaves the modal's frame whatever else its data says, so an answer that redirects is a visit" do
    form = Nokogiri::HTML5.fragment(render(:modal_form, data: { turbo_stream: true })).at_css("form")

    assert_equal [ "_top", "true" ], [ form["data-turbo-frame"], form["data-turbo-stream"] ]
  end

  test "the toasts shown while it is open are read aloud, as on the page" do
    container = Nokogiri::HTML5.fragment(render(:modal_form)).at_css("[data-modal-target=toasts]")

    assert_equal "polite", container["aria-live"]
  end

  test "any other wrapper is reported, by the modal's title, the part and what it sits in, and so is its form" do
    problems = ModalStructure.problems(render(:form_with))

    assert_equal [
      "Sample: .modal__body sits in form.sample-form, not in the dialog or its .modal__form",
      "Sample: .modal__footer sits in form.sample-form, not in the dialog or its .modal__form",
      "Sample: a form to /samples stays in the modal's frame"
    ], problems
  end

  test "a second body, or anything after the footer, is reported too" do
    html = <<~HTML
      <div class="modal__dialog"><h2 class="modal__title">Edit list</h2>
        <form class="modal__form" data-turbo-frame="_top"><div class="modal__body"></div><footer class="modal__footer"></footer></form>
        <div class="modal__body">sharing</div>
      </div>
    HTML

    assert_equal [ "Edit list: 2 .modal__body, one at most", "Edit list: something follows its .modal__footer" ], ModalStructure.problems(html)
  end

  test "a size it doesn't have is a mistake rather than a medium dialog" do
    assert_raises(ArgumentError) { Components::Modal.new(size: "small") }
  end

  private

  def render(wrapper, data: {}) = ApplicationController.render(Sample.new(wrapper:, data:), layout: false)
end
