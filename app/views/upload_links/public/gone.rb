# frozen_string_literal: true

# A link that leads nowhere: spent, expired, revoked, or never there (a
# link to a file not yet whole reads the same), or too many tries from one
# place.
class Views::UploadLinks::Public::Gone < Views::Base
  def initialize(reason:)
    @reason = reason
  end

  def view_template
    div(class: "auth-hero public-upload-link") do
      div(class: "auth-card public-upload-link__card") do
        div(class: "auth-card__header") do
          div(class: "public-upload-link__icon public-upload-link__icon--gone") { render Components::Icon.new("fa-link-slash") }
          h1(class: "auth-card__title") { t("upload_links.public.gone.title") }
          p(class: "auth-card__subtitle") { t("upload_links.public.gone.#{@reason}") }
        end
      end
    end
  end
end
