# frozen_string_literal: true

# The admin's password, asked before a press that acts on someone
# else's account (ReauthenticatesAdmin). It sends the same press again,
# to the same address with the same method, with the password beside it.
class Views::Admin::Modals::Password < Views::Base
  # subtitle: what the press does ("Remove Bob from the household");
  # submit: its button; wrong: the password just typed wasn't theirs.
  def initialize(url:, method:, subtitle:, submit:, danger: false, wrong: false)
    @url = url
    @method = method
    @subtitle = subtitle
    @submit = submit
    @danger = danger
    @wrong = wrong
  end

  def view_template
    render Components::Modal.new(size: :small) do |modal|
      modal.modal_header(title: t("admin.password_check.title"), subtitle: @subtitle, icon: "fa-lock")
      modal.modal_form(url: @url, method: @method) do |form|
        modal.modal_body do
          render Views::Admin::PasswordCheck.new(form: form, wrong: @wrong, autofocus: true,
                                                 why: t("admin.password_check.why_account", minutes: ::Admin::Sudo::FOR.in_minutes.to_i))
        end
        modal.modal_footer do
          div(class: "modal__footer-main") do
            button(type: "submit", class: "modal__btn #{@danger ? "modal__btn--danger" : "modal__btn--primary"}") { @submit }
          end
        end
      end
    end
  end
end
