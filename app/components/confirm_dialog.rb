# frozen_string_literal: true

# The app's own "are you sure?", in its colours and the reader's language,
# asked before every press that carries `confirm:` (data-turbo-confirm). The
# layout renders it once; confirm_dialog_controller.js puts the question in
# and names the confirming button after the press that asked.
class Components::ConfirmDialog < Components::Base
  ID = "confirm_dialog"

  def view_template
    dialog(id: ID, class: "confirm-dialog", aria: { labelledby: "#{ID}_question" }, data: dialog_data) do
      form(method: "dialog", class: "confirm-dialog__form") do
        p(id: "#{ID}_question", class: "confirm-dialog__question", data: { confirm_dialog_target: "question" })
        div(class: "confirm-dialog__actions") do
          button(type: "submit", value: "cancel", class: "modal__btn modal__btn--cancel", autofocus: true,
                 data: { confirm_dialog_target: "dismiss" }) { t("confirm_dialog.cancel") }
          button(type: "submit", value: "confirm", class: "modal__btn modal__btn--primary",
                 data: { confirm_dialog_target: "confirm" }) { t("confirm_dialog.confirm") }
        end
      end
    end
  end

  private

  def dialog_data
    {
      controller: "confirm-dialog",
      action: "click->confirm-dialog#backdropClick close->confirm-dialog#closed " \
              "turbo:before-morph-element->confirm-dialog#holdWhileOpen",
      confirm_dialog_words_value: { confirm: t("confirm_dialog.confirm"), dismiss: t("confirm_dialog.cancel") }.to_json
    }
  end
end
