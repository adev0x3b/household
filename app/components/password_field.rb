# frozen_string_literal: true

# A password field and the button that shows what was typed
# (password_toggler_controller.js), on every page that asks for one: signing
# in, the first account, accepting an invitation, a password link. A new
# password (`new_password: true`) says the rule under it (Devise's
# password_length), and the browser holds the field to it too.
#
#   render Components::PasswordField.new(form: f, attribute: :password, label: t("…"), new_password: true)
class Components::PasswordField < Components::Base
  # label_hidden: the label is for screen readers only (the sign-in card
  # shows placeholders); errors: what the server refused in it; options go
  # to the input (placeholder, autofocus…).
  def initialize(form:, attribute:, label:, new_password: false, label_hidden: false, errors: [], **options)
    @form = form
    @attribute = attribute
    @label = label
    @new_password = new_password
    @label_hidden = label_hidden
    @errors = errors
    @options = options
  end

  def view_template
    render Components::Field.new(label: @label, control_id: id, label_hidden: @label_hidden, control: false, errors: @errors,
                                 data: { controller: "password-toggler" }) do |field|
      div(class: "control auth-card__field-wrapper") do
        @form.password_field @attribute, **input_options(field)
        button(type: "button", class: "auth-card__toggle-password", aria: { label: t("password_field.show"), pressed: "false" },
               data: { action: "password-toggler#toggle", password_toggler_target: "button" }) do
          render Components::Icon.new("fa-eye", data: { password_toggler_target: "icon" })
        end
      end
      p(class: "help", id: hint_id) { t("password_field.rule", count: length.min) } if rule?
    end
  end

  private

  # The rule and what was refused both describe the input, the rule first.
  def input_options(field)
    aria = field.aria
    options = { id: id, class: "input is-medium", required: true, maxlength: length.max,
                autocomplete: @new_password ? "new-password" : "current-password", data: { password_toggler_target: "input" } }
    if rule?
      options[:minlength] = length.min
      aria = aria.merge(describedby: [ hint_id, aria[:describedby] ].compact.join(" "))
    end
    options[:aria] = aria if aria.any?
    options.merge(@options)
  end

  # The rule goes under the new password, not its confirmation.
  def rule? = @new_password && @attribute == :password

  def length = Devise.password_length
  def id = @form.field_id(@attribute)
  def hint_id = "#{id}_rule"
end
