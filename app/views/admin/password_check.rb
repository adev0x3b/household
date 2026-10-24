# frozen_string_literal: true

# The admin's password, asked again inside the form that needs it
# (Admin::Sudo): why it is asked, and what was wrong with the last one.
# The account modal and the two settings pages draw it alike.
class Views::Admin::PasswordCheck < Views::Base
  # form: the builder of the form it posts with; why: the sentence under
  # the field; wrong: the password just typed wasn't theirs. The rest goes
  # to the input: a modal that asks for nothing else wants it focused and
  # required, a settings page whose Test button sends the same form doesn't.
  def initialize(form:, why:, wrong: false, **input)
    @form = form
    @why = why
    @wrong = wrong
    @input = input
  end

  def view_template
    render(Components::Notice.new(tone: :critical) { p { t("admin.password_check.wrong") } }) if @wrong
    render Components::PasswordField.new(form: @form, attribute: :password, label: t("admin.password_check.password_label"), **@input)
    p(class: "help") { @why }
  end
end
