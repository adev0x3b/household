# frozen_string_literal: true

# What whoever has a link sees: the file's name, size and kind, who shared
# it, how long the link is good for, a password field when it has one, and
# the Download button. The sign-in page's card, since there is no account here.
class Views::UploadLinks::Public::Show < Views::Base
  include Phlex::Rails::Helpers::FormWith

  def initialize(link:, token:, error: nil)
    @link = link
    @token = token
    @upload = link.upload
    @error = error
  end

  def view_template
    div(class: "auth-hero public-upload-link") do
      div(class: "auth-card public-upload-link__card") do
        div(class: "auth-card__header") do
          div(class: "public-upload-link__icon") { render Views::Uploads::Icon.new(@upload) }
          h1(class: "auth-card__title public-upload-link__name") { @upload.name }
          p(class: "auth-card__subtitle") { t("upload_links.public.show.shared_by", name: @upload.profile.display_name, size: size) }
        end
        p(class: "public-upload-link__terms") { terms }
        form_with(url: public_upload_link_path(@token), method: :post, data: { turbo: false }) do |f|
          password_field(f) if @link.protected?
          div(class: "field") do
            div(class: "control") { f.submit t("upload_links.public.show.download"), class: "button is-primary is-fullwidth is-medium" }
          end
        end
      end
    end
  end

  private

  def size = ActiveSupport::NumberHelper.number_to_human_size(@upload.byte_size, locale: I18n.locale)

  def terms
    left = @link.max_downloads ? t("upload_links.public.show.downloads_left", count: @link.max_downloads - @link.downloads_count) : t("upload_links.public.show.unlimited")
    "#{left} · #{t("upload_links.public.show.until", date: l(@link.expires_at, format: :long))}"
  end

  def password_field(f)
    render Components::Field.new(label: t("upload_links.public.show.password_label"), control_id: f.field_id(:password),
                                 errors: [ @error ].compact) do |field|
      f.password_field :password, class: "input is-medium", autocomplete: "off", required: true, autofocus: true, aria: field.aria
    end
  end
end
