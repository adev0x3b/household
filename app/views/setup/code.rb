# frozen_string_literal: true

# The setup page's first screen: the one-time code, and nothing else until
# it is given (SetupCodesController). Without a code the copy can't be set
# up, so the page says how to make one on the machine instead of a form.
class Views::Setup::Code < Views::Base
  include Phlex::Rails::Helpers::FormWith

  # available: this copy has a code to ask for; wrong: the last one typed wasn't it.
  def initialize(available:, wrong: false)
    @available = available
    @wrong = wrong
  end

  def page_title = t("setup.title")

  def view_template
    div(class: "auth-hero") do
      div(class: "auth-card") do
        div(class: "auth-card__header") do
          h1(class: "auth-card__title") { t("setup.title") }
          p(class: "auth-card__subtitle") { subtitle }
        end
        if @available
          render_form
        else
          render_command
        end
      end
    end
  end

  private

  def subtitle
    if @available
      t("setup.code.subtitle")
    else
      t("setup.code.none")
    end
  end

  def render_form
    form_with(url: setup_code_path, scope: :setup_code, data: { turbo: false }) do |f|
      render Components::Field.new(label: t("setup.code.label"), control_id: "setup_code_code", help: t("setup.code.help"),
                                   errors: (@wrong ? [ t("setup.code.wrong") ] : [])) do |field|
        f.text_field :code, value: nil, class: "input is-medium auth-card__code-input", required: true, autofocus: true,
                            autocomplete: "one-time-code", autocapitalize: "characters", spellcheck: "false",
                            placeholder: t("setup.code.placeholder"), aria: field.aria
      end
      div(class: "field") do
        div(class: "control") { f.submit t("setup.code.submit"), class: "button is-primary is-fullwidth is-medium" }
      end
    end
  end

  def render_command
    p(class: "auth-card__note") { t("setup.code.command_intro") }
    pre(class: "auth-card__command") { code { "bin/rails setup:code" } }
  end
end
