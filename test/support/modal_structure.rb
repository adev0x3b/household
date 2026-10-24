# frozen_string_literal: true

# Every modal a test renders keeps the shape Components::Modal describes:
# one body and a footer, sitting in the dialog itself or in the one form
# around both (Components::Modal#modal_form, Components::Form), the footer
# last. Any other wrapper keeps the dialog's height from the body, so a
# long body pushes the footer, and the modal's action with it, out of
# sight; anything after the footer puts the action mid-dialog. Every form
# in it leaves the modal's frame, or an answer that redirects finds no frame
# to draw in. Checked on every response, the way Prosopite watches every
# request's queries.
module ModalStructure
  FORM = "modal__form"

  # What is wrong with the modals in `html`, one line each.
  def self.problems(html)
    Nokogiri::HTML5.fragment(html).css(".modal__dialog").flat_map do |dialog|
      name = dialog.at_css(".modal__title")&.text.to_s.squish.presence || "a modal"
      bodies = dialog.css(".modal__body")
      [
        *dialog.css(".modal__body, .modal__footer").filter_map { |part| misplaced(dialog, part, name) },
        ("#{name}: #{bodies.size} .modal__body, one at most" if bodies.size > 1),
        *dialog.css(".modal__footer").filter_map { |footer| "#{name}: something follows its .modal__footer" if followed?(dialog, footer) },
        *dialog.css("form").reject { _1["data-turbo-frame"] == "_top" }.map { "#{name}: a form to #{_1["action"]} stays in the modal's frame" }
      ].compact
    end
  end

  def self.misplaced(dialog, part, name)
    wrappers = part.ancestors.take_while { _1 != dialog }
    return if wrappers.all? { _1.classes.include?(FORM) } && wrappers.size <= 1

    path = wrappers.reverse.map { [ _1.name, *_1.classes ].join(".") }.join(" > ")
    "#{name}: .#{part.classes.first} sits in #{path}, not in the dialog or its .#{FORM}"
  end

  # Whether anything comes after the footer, in its form or in the dialog.
  def self.followed?(dialog, footer)
    [ footer, *footer.ancestors.take_while { _1 != dialog } ].any? { _1.next_element }
  end

  module CheckEveryResponse
    def process(...)
      super.tap do
        body = response.body.to_s
        next unless body.include?("modal__dialog")

        problems = ModalStructure.problems(body)
        raise Minitest::Assertion, problems.join("\n") if problems.any?
      end
    end
  end
end

ActionDispatch::Integration::Session.prepend(ModalStructure::CheckEveryResponse)
