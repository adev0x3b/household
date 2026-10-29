# frozen_string_literal: true

# /account: the signed-in person's own account. Their address, where the
# app's mail goes once it is confirmed: whether it is, a new one waiting
# for its link, that link mailed again, and reminders that couldn't be
# mailed lately; then a form to change it and a form to change the
# password, each asking for the password in use.
class Views::Accounts::Show < Views::Base
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::ButtonTo

  CONFIRMED = Components::StatusLook.new(tone: :good)
  NOT_CONFIRMED = Components::StatusLook.new(tone: :warning)

  # mail: whether the app mails (Emails.enabled?). reminders_by_mail,
  # password_link_by_mail: whether the person's reminders may come by email
  # (Emails.for_reminders), and a link for a forgotten password
  # (Profiles::RequestPasswordLink.mailable?). confirmation_on_its_way:
  # whether their link to confirm an address is still to go out
  # (OutgoingEmail.confirmation_on_its_way?). reminders_not_mailed: how
  # many of the person's reminders couldn't be mailed in the last day.
  # email_change, password_change: a form as a refused save left it; a
  # fresh one otherwise.
  def initialize(profile:, mail:, reminders_by_mail: false, password_link_by_mail: false, confirmation_on_its_way: false,
                 reminders_not_mailed: 0, email_change: nil, password_change: nil)
    @profile = profile
    @mail = mail
    @reminders_by_mail = reminders_by_mail
    @password_link_by_mail = password_link_by_mail
    @confirmation_on_its_way = confirmation_on_its_way
    @reminders_not_mailed = reminders_not_mailed
    @email_change = email_change || Accounts::EmailChange.new(profile)
    @password_change = password_change || Accounts::PasswordChange.new(profile)
  end

  def page_title = t("accounts.show.title")

  def view_template
    div(class: "report-page account") do
      render Components::PageHeader.new(title: t("accounts.show.title"), subtitle: t("accounts.show.signed_in_as", username: @profile.username))
      address
      address_form
      password_form
    end
  end

  private

  def address
    render Components::Panel.new(title: t("accounts.show.address.title"), hint: address_hint) do
      p(class: "account__address") do
        span(class: "account__value") { @profile.email }
        render address_badge if @mail || @profile.email_confirmed?
      end
      if @profile.unconfirmed_email
        waiting
      elsif @mail && !@profile.email_confirmed?
        link_sent
        actions { send_link(t("accounts.show.address.send_link")) }
      end
      not_mailed if @mail && @reminders_not_mailed.positive?
    end
  end

  # Reminders the relay or the budgets kept from going out lately: the
  # person learns not to count on their mail alone.
  def not_mailed
    render Components::Notice.new do
      p { t("accounts.show.address.reminders_not_mailed", count: @reminders_not_mailed) }
    end
  end

  def address_hint
    return t("accounts.show.address.hint_no_mail") unless @mail
    return t("accounts.show.address.hint_unconfirmed") unless @profile.email_confirmed?

    confirmed_hint
  end

  # What a confirmed address is mailed besides the news of the account
  # itself: the admin's way back is the server, never a link by mail, and
  # an installation may allow no reminder mail.
  def confirmed_hint
    if @reminders_by_mail && @password_link_by_mail then t("accounts.show.address.hint_confirmed")
    elsif @reminders_by_mail then t("accounts.show.address.hint_confirmed_reminders")
    elsif @password_link_by_mail then t("accounts.show.address.hint_confirmed_password_link")
    else t("accounts.show.address.hint_confirmed_notices")
    end
  end

  def address_badge
    return CONFIRMED.badge(label: t("accounts.show.address.confirmed")) if @profile.email_confirmed?

    NOT_CONFIRMED.badge(label: t("accounts.show.address.not_confirmed"))
  end

  # A new address asked for: where its link went, until when it works, and
  # the ways out (the link again, or keeping the address in use).
  def waiting
    render Components::Notice.new(tone: :action) do
      p { t("accounts.show.waiting.body", address: @profile.unconfirmed_email) }
      link_sent
      p { t("accounts.show.waiting.no_mail") } unless @mail
    end
    actions do
      send_link(t("accounts.show.waiting.send_again")) if @mail
      keep = t("accounts.show.waiting.keep", address: @profile.email)
      button_to(keep, account_email_change_path, method: :delete, class: "modal__btn modal__btn--cancel", form_class: "account__press")
    end
  end

  # A link whose mail still waits says so rather than when it was made: a
  # try that didn't go out may have left one in place.
  def link_sent
    return p(class: "report-hint") { t("accounts.show.address.link_on_its_way") } if @confirmation_on_its_way
    return unless @profile.email_confirmation_open?

    expires = @profile.email_confirmation_sent_at + Profile::EMAIL_CONFIRMATION_FOR
    p(class: "report-hint") do
      t("accounts.show.address.link_sent", sent: l(@profile.email_confirmation_sent_at, format: :short), expires: l(expires, format: :short))
    end
  end

  def send_link(label)
    button_to(label, account_email_confirmation_link_path, class: "modal__btn modal__btn--primary", form_class: "account__press")
  end

  def address_form
    render Components::Panel.new(title: t("accounts.show.change_address.title"), hint: change_address_hint) do
      form_with(model: @email_change, scope: :email_change, url: account_email_change_path, method: :post, class: "report-form") do |f|
        render Components::ErrorSummary.new(record: @email_change)
        form_field(f, :email, label: t("accounts.show.change_address.email"), required: true) do |field|
          f.email_field :email, class: "input", required: true, autocomplete: "email", autocapitalize: "none", spellcheck: "false",
                                aria: field.aria
        end
        current_password(f)
        actions { submit(t("accounts.show.change_address.submit")) }
      end
    end
  end

  def change_address_hint = @mail ? t("accounts.show.change_address.hint") : t("accounts.show.change_address.hint_no_mail")

  def password_form
    render Components::Panel.new(title: t("accounts.show.change_password.title"), hint: t("accounts.show.change_password.hint")) do
      form_with(model: @password_change, scope: :password_change, url: account_password_path, method: :patch, class: "report-form") do |f|
        render Components::ErrorSummary.new(record: @password_change)
        # Password managers file the new password under the username.
        input(type: "text", value: @profile.username, autocomplete: "username", hidden: true, readonly: true, tabindex: "-1")
        current_password(f)
        new_password(f, :password)
        new_password(f, :password_confirmation)
        actions { submit(t("accounts.show.change_password.submit")) }
      end
    end
  end

  def current_password(f)
    render Components::PasswordField.new(form: f, attribute: :current_password, label: t("accounts.show.current_password"),
                                         errors: Forms::Errors.new(f.object).for(:current_password))
  end

  def new_password(f, attribute)
    render Components::PasswordField.new(form: f, attribute:, label: t("accounts.show.change_password.#{attribute}"), new_password: true,
                                         errors: Forms::Errors.new(f.object).for(attribute))
  end

  def submit(label)
    button(type: "submit", class: "modal__btn modal__btn--primary") { label }
  end

  def actions(&) = div(class: "account__actions", &)
end
