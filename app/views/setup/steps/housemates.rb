# frozen_string_literal: true

# The first setup's last question (Setup::Housemates): who else lives here,
# a row each. Each gets an invitation link at the end, to hand over.
class Views::Setup::Steps::Housemates < Views::Base
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("setup.steps.housemates.title"), hint: t("setup.steps.housemates.hint")) do
      fieldset(class: "setup-housemates") do
        legend(class: "is-sr-only") { t("setup.steps.housemates.title") }
        render Components::NestedFields.new(rows_class: "setup-housemates__rows", row_class: "setup-housemates__row",
                                            prefix: ->(index) { "#{@form.object_name}[people][#{index}]" },
                                            add_label: t("setup.steps.housemates.add"), remove_label: t("setup.steps.housemates.remove"),
                                            saved_whole: true, danger: false, errors: row_errors) do |fields|
          fields.rows { @section.people.each_with_index { |person, index| row(fields, person, index) } }
          fields.template { row(fields, ::Setup::Housemate.new, Components::NestedFields::NEW_ROW) }
        end
      end
    end
  end

  private

  # Each row is a Setup::Housemate of its own, so its errors are its record's.
  def row_errors = @section.people.each_with_index.to_h { |person, index| [ index, Forms::Errors.new(person) ] }

  def row(fields, person, index)
    fields.row(index:) do |prefix, marks|
      input(type: "text", name: "#{prefix}[first_name]", value: person.first_name, autocomplete: "off", class: "input setup-housemates__name",
            placeholder: t("setup.steps.housemates.first_name"),
            aria: { label: t("setup.steps.housemates.first_name"), **marks.aria(:first_name) })
      input(type: "email", name: "#{prefix}[email]", value: person.email, required: true, autocomplete: "off",
            placeholder: t("setup.steps.housemates.email"),
            class: "input setup-housemates__email", aria: { label: t("setup.steps.housemates.email"), **marks.aria(:email) })
    end
  end
end
