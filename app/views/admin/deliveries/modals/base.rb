# frozen_string_literal: true

# A press before it is made: each kind's modal says what it will do in its
# `body`, and this frame asks for what the press needs from the admin.
class Views::Admin::Deliveries::Modals::Base < Views::Base
  def initialize(press:)
    @press = press
    @pipeline = press.pipeline
  end

  def view_template
    render Components::Modal.new(size: :medium) do |modal|
      modal.modal_header(title: title, subtitle: t("admin.deployment.modals.#{kind}.subtitle", **words), icon: @press.icon)
      modal.modal_form(url: admin_delivery_requests_path, method: :post, scope: :press, class: "deployment-modal", data: form_data) do |form|
        input(type: "hidden", name: "kind", value: kind)
        modal.modal_body do
          errors if @press.errors.any?
          live_warning if @pipeline.live?
          body(form)
          fields(form) unless @press.blocked?
        end
        modal.modal_footer { div(class: "modal__footer-main") { submit } unless @press.blocked? }
      end
    end
  end

  private

  # What the press will do, and the fields only this kind has.
  def body(form) = raise(NotImplementedError)

  def kind = @press.kind
  def title = t("admin.deployment.modals.#{kind}.title", **words)

  # What the title, the subtitle and the button name; a kind adds its own.
  def words = { destination: destination_name, version: phrase, ref: @press.ref, phrase: phrase }

  def environment = @press.environment
  def destination_name = @press.destination && t("admin.deployment.destinations.#{@press.destination}")
  def phrase = @press.phrase
  def dev = @pipeline.dev
  def some_branch = dev.branch || t("admin.deployment.environment.some_branch")

  def form_data
    return {} unless @press.typed?

    { controller: "typed-confirm", typed_confirm_phrase_value: phrase }
  end

  def errors
    render Components::Notice.new(tone: :critical) do
      ul { @press.errors.each { |error| li { error.message } } }
    end
  end

  def live_warning
    render Components::Notice.new(tone: :neutral) { p { t("admin.deployment.modals.in_progress") } }
  end

  def line(&) = p(class: "deployment-modal__line", &)
  def hint(&) = p(class: "report-hint", &)
  def ships(commits) = render(Views::Admin::Deliveries::Ships.new(commits))

  def fields(form)
    reason(form)
    typed(form) if @press.typed?
    password(form) if @press.password?
  end

  def reason(form)
    render Components::Field.new(label: t("admin.deployment.modals.reason_label#{"_optional" unless @press.reason_required?}"),
                                 control_id: "press_reason") do
      form.text_field :reason, value: @press.reason, class: "input", autocomplete: "off", maxlength: 140,
                               placeholder: t("admin.deployment.modals.reason_placeholder"), required: @press.reason_required?
    end
  end

  def typed(form)
    render Components::Field.new(label: t("admin.deployment.modals.typed_label", phrase: phrase), control_id: "press_typed") do
      form.text_field :typed, value: "", class: "input report-mono", autocomplete: "off", autocapitalize: "off", spellcheck: "false", inputmode: "text",
                              data: { typed_confirm_target: "input", action: "input->typed-confirm#check" }
    end
  end

  def password(form)
    render Components::Field.new(label: t("admin.deployment.modals.password_label"), control_id: "press_password",
                                 help: t("admin.deployment.modals.password_help", minutes: ::Admin::Sudo::FOR.in_minutes.to_i)) do
      form.password_field :password, class: "input", autocomplete: "current-password"
    end
  end

  def submit
    button(type: "submit", class: "modal__btn #{@press.danger? ? "modal__btn--danger" : "modal__btn--primary"}",
           disabled: (true if @press.typed?), data: ({ typed_confirm_target: "submit" } if @press.typed?)) do
      t("admin.deployment.modals.#{kind}.submit", **words)
    end
  end
end
