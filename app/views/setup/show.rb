# frozen_string_literal: true

# The first setup (SetupController): every step of Setup::Form in one form,
# shown a step at a time by setup_wizard_controller.js, with where the
# person is, Back and Next, and a last step that lists every answer before
# Create. Without JavaScript every step shows at once. What was typed comes
# back with the errors, opened at the first step that has one; passwords
# and keys never do.
class Views::Setup::Show < Views::Base
  include Phlex::Rails::Helpers::FormWith

  def initialize(form:)
    @form = form
  end

  def page_title = t("setup.title")

  def view_template
    div(class: "report-page setup") do
      header(class: "setup__header") do
        h1(class: "setup__title") { t("setup.title") }
        p(class: "report-hint") { t("setup.subtitle") }
      end
      @form.steps.each { |step| render Components::ErrorSummary.new(record: step) }
      form_with(url: setup_path, scope: :setup, class: "report-form setup__form", data: wizard_data) do |f|
        p(class: "setup__progress", hidden: true, aria: { live: "polite" }, data: { setup_wizard_target: "progress" })
        @form.steps.each { |step| step_section(f, step) }
        review
        navigation
      end
    end
  end

  private

  # The page opens at the first step with an error.
  def wizard_data
    first = @form.first_invalid
    { controller: "setup-wizard", action: "keydown.enter->setup-wizard#enter", setup_wizard_start_value: first ? @form.steps.index(first) : 0,
      setup_wizard_progress_value: t("setup.progress"), setup_wizard_on_value: t("setup.review.on"),
      setup_wizard_off_value: t("setup.review.off"), setup_wizard_set_value: t("setup.review.set"),
      setup_wizard_unset_value: t("setup.review.unset"), setup_wizard_change_value: t("setup.review.change") }
  end

  def step_section(f, step)
    div(class: "setup__step", data: { setup_wizard_target: "step" }) do
      f.fields_for(step.class.param_key, step) do |fields|
        render Views::Setup::Steps::BY_STEP.fetch(step.class).new(form: fields, section: step)
      end
    end
  end

  def review
    div(class: "setup__step", hidden: true, data: { setup_wizard_target: "step review" }) do
      render Components::Panel.new(title: t("setup.review.title"), hint: t("setup.review.hint")) do
        div(class: "setup__summary", data: { setup_wizard_target: "summary" })
      end
    end
  end

  def navigation
    div(class: "report-footer setup__nav") do
      button(type: "button", class: "modal__btn modal__btn--cancel", hidden: true, data: { setup_wizard_target: "back", action: "setup-wizard#back" }) do
        render Components::Icon.new("fa-arrow-left")
        whitespace
        plain t("setup.back")
      end
      button(type: "button", class: "modal__btn modal__btn--primary", hidden: true, data: { setup_wizard_target: "next", action: "setup-wizard#next" }) do
        plain t("setup.next")
        whitespace
        render Components::Icon.new("fa-arrow-right")
      end
      # Create is sent without Turbo, so its answer can show the invitation
      # links (Views::Setup::Done); the assistant step's Test press is a
      # Turbo request that answers in place.
      button(type: "submit", class: "modal__btn modal__btn--primary", data: { setup_wizard_target: "create", action: "setup-wizard#create", turbo: "false" }) do
        render Components::Icon.new("fa-house-circle-check")
        whitespace
        plain t("setup.submit")
      end
    end
  end
end
