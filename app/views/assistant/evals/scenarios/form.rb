# frozen_string_literal: true

# Writing a scenario, one card per part: the basics, what exists beforehand
# (seeds), what the user says turn by turn, and what must be true afterwards
# (checks). The footer stays in reach: Try once runs the form as it is,
# without saving, on the provider and model beside it (its run shows below
# the form and comes into view; what stops it is a toast); Save writes the
# file. Deleting a saved scenario is the navbar's.
class Views::Assistant::Evals::Scenarios::Form < Views::Base
  TRY_ID = "eval-try"

  def initialize(draft:, models:, lenient: false)
    @draft = draft
    @models = models
    @lenient = lenient
  end

  def page_title = @draft.persisted? ? @draft.original_name : t("assistant.evals.new_scenario")

  def navbar_controls
    return unless @draft.persisted?

    delete = Components::Action.new(href: routes.assistant_evals_scenario_path(@draft.original_name), icon: "fa-trash", method: :delete,
                                    label: t("assistant.evals.form.delete"), confirm: t("assistant.evals.form.delete_confirm"))
    Components::PageControls.new(actions: [ delete ])
  end

  def view_template
    div(class: "report-page evals") do
      render Components::PageHeader.new(title: page_title, back_href: assistant_evals_scenarios_path, back_label: t("assistant.evals.back_to_scenarios"))
      notices
      render Views::Assistant::Evals::Errors.new(messages: @draft.errors.full_messages)

      form(action: @draft.persisted? ? assistant_evals_scenario_path(@draft.original_name) : assistant_evals_scenarios_path,
           method: "post", class: "report-form eval-form", data: { controller: "eval-scenario-form" }) do
        basics
        seeds
        messages
        expectations
        footer
      end
      div(id: TRY_ID, class: "eval-form__try")
    end
  end

  private

  def notices
    if @draft.source_has_comments?
      render(Components::Notice.new(tone: :action)) { plain t("assistant.evals.form.comments_warning") }
    end
    render(Components::Notice.new(tone: :action)) { plain t("assistant.evals.form.lenient_warning") } if @lenient
  end

  def basics
    render Components::Panel.new(title: t("assistant.evals.form.basics")) do
      div(class: "report-fields") do
        field("name", t("assistant.evals.form.name"), hint: t("assistant.evals.form.name_hint")) do
          input(type: "text", id: "scenario_name", name: "scenario[name]", value: @draft.name, class: "input report-mono", required: true,
                pattern: "\\d{2}_[a-z0-9_]+", spellcheck: "false")
        end
        field("today", t("assistant.evals.form.today"), hint: t("assistant.evals.form.today_hint")) do
          input(type: "date", id: "scenario_today", name: "scenario[today]", value: @draft.today, class: "input", required: true)
        end
      end
      field("description", t("assistant.evals.form.description")) do
        textarea(id: "scenario_description", name: "scenario[description]", rows: 2, class: "textarea") { @draft.description }
      end
      field("tags", t("assistant.evals.form.tags"), hint: t("assistant.evals.form.tags_hint")) do
        input(type: "text", id: "scenario_tags", name: "scenario[tags]", value: @draft.tags.join(", "), class: "input", autocomplete: "off")
      end
    end
  end

  def seeds
    render Components::Panel.new(title: t("assistant.evals.form.seeds"), hint: t("assistant.evals.form.seeds_hint")) do
      fieldset(class: "eval-seeds") do
        legend(class: "is-sr-only") { t("assistant.evals.form.seeds") }
        AssistantEval::Seeds.names.each do |seed|
          label(class: "eval-seeds__seed") do
            input(type: "checkbox", name: "scenario[seed][]", value: seed, checked: @draft.seed.include?(seed))
            span(class: "report-mono") { seed }
          end
        end
      end
    end
  end

  def messages
    render Components::Panel.new(title: t("assistant.evals.form.messages"), hint: t("assistant.evals.form.messages_hint")) do
      ol(class: "eval-form__rows", data: { eval_scenario_form_target: "messages" }) do
        @draft.messages.each { |message| message_row(message) }
      end
      template(data: { eval_scenario_form_target: "messageTemplate" }) { message_row("") }
      add_button(:addMessage, t("assistant.evals.form.add_message"))
    end
  end

  def message_row(message)
    li(class: "eval-form__row", data: { row: true }) do
      textarea(name: "scenario[messages][]", rows: 2, class: "textarea", aria: { label: t("assistant.evals.form.message") }) { message }
      remove_button
    end
  end

  def expectations
    render Components::Panel.new(title: t("assistant.evals.form.checks"), hint: t("assistant.evals.form.checks_hint")) do
      ol(class: "eval-form__rows", data: { eval_scenario_form_target: "expects" }) do
        @draft.expect.each { |row| expect_row(row["check"], row["argument"]) }
      end
      template(data: { eval_scenario_form_target: "expectTemplate" }) { expect_row(nil, "") }
      add_button(:addExpect, t("assistant.evals.form.add_check"))
    end
  end

  def expect_row(name, argument)
    chosen = name && AssistantEval::Checks.named(name)
    li(class: "eval-form__row eval-form__row--check", data: { row: true }) do
      div(class: "eval-form__check-fields") do
        div(class: "select is-fullwidth") do
          select(name: "scenario[expect][][check]", aria: { label: t("assistant.evals.form.check") }, data: { action: "change->eval-scenario-form#describe" }) do
            option(value: "") { t("assistant.evals.form.pick_check") } unless name
            AssistantEval::Checks.all.each do |check|
              option(value: check.key, selected: check.key == name, data: { help: check.argument, example: AssistantEval::ScenarioDraft.dump(check.example) }) { check.key }
            end
          end
        end
        textarea(name: "scenario[expect][][argument]", rows: 3, class: "textarea report-mono", aria: { label: t("assistant.evals.form.argument") },
                 placeholder: chosen && AssistantEval::ScenarioDraft.dump(chosen.example)) { argument }
        p(class: "help", data: { check_help: true }) { chosen&.argument }
      end
      remove_button
    end
  end

  # What acts on the whole form: try it once (on this provider and model), or save it.
  def footer
    div(class: "report-footer") do
      div(class: "report-footer__fields eval-model-fields") { render Views::Assistant::Evals::ModelFields.new(models: @models, compact: true) }
      button(type: "submit", formaction: try_assistant_evals_scenarios_path, class: "modal__btn modal__btn--cancel") do
        render Components::Icon.new("fa-flask")
        whitespace
        plain t("assistant.evals.form.try")
      end
      # Only Save sends the PATCH override: Try posts to its own route.
      button(type: "submit", class: "modal__btn modal__btn--primary", **(@draft.persisted? ? { name: "_method", value: "patch" } : {})) do
        render Components::Icon.new("fa-floppy-disk")
        whitespace
        plain t("assistant.evals.form.save")
      end
    end
  end

  def field(name, text, hint: nil, &)
    render Components::Field.new(label: text, control_id: "scenario_#{name}", help: hint, &)
  end

  # Adds a row at the end of its list.
  def add_button(action, text)
    button(type: "button", class: "eval-form__add", data: { action: "eval-scenario-form##{action}" }) do
      render Components::Icon.new("fa-plus")
      whitespace
      plain text
    end
  end

  def remove_button
    render Components::ItemAction.new(icon: "fa-xmark", label: t("assistant.evals.form.remove"), danger: true,
                                      data: { action: "eval-scenario-form#remove" })
  end
end
