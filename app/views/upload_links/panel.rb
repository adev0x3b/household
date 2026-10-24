# frozen_string_literal: true

# A file's public links on its page: every one there was, live, spent, expired
# or revoked, each with what it allowed and what it was used for. The
# address of one just made is shown once, in its own modal
# (Views::UploadLinks::Modals::Created). Replaced as one unit when a link
# is made or revoked; a revoked link keeps its line but loses its button, so
# the focus goes on to the next live link's, else the panel's.
class Views::UploadLinks::Panel < Views::Base
  LOOKS = {
    active: Components::StatusLook.new(tone: :good),
    exhausted: Components::StatusLook.new(tone: :neutral, icon: "fa-circle-check"),
    expired: Components::StatusLook.new(tone: :neutral, icon: "fa-clock"),
    revoked: Components::StatusLook.new(tone: :warning, icon: "fa-link-slash")
  }.freeze

  def self.dom_id(upload) = "upload-#{upload.id}-links"
  def self.revoke_id(link) = "upload-link-#{link.id}-revoke"

  # links: every link made to the upload, newest first (Uploads::Page).
  def initialize(upload:, links:)
    @upload = upload
    @links = links
  end

  def view_template
    div(id: self.class.dom_id(@upload), class: "upload-links", tabindex: "-1") do
      if @links.any?
        ul(class: "upload-links__list") { @links.each { |link| item(link) } }
      else
        render Components::EmptyState.new(icon: "fa-link", message: t("upload_links.panel.empty"))
      end
    end
  end

  private

  def item(link)
    li(class: [ "upload-links__item", ("upload-links__item--#{link.state}") ]) do
      div(class: "upload-links__item-main") do
        div(class: "upload-links__item-head") do
          state_badge(link)
          render Components::Icon.new("fa-lock", label: t("upload_links.panel.protected"), class: "upload-links__lock") if link.protected?
        end
        p(class: "upload-links__item-meta") { meta(link) }
      end
      if link.state == :active
        render Components::ItemAction.new(id: self.class.revoke_id(link), href: upload_link_path(link), icon: "fa-link-slash", label: t("upload_links.panel.revoke"),
                                          turbo_stream: true, method: :delete, confirm: t("upload_links.panel.revoke_confirm"), danger: true,
                                          data: { focus_fallback: focus_fallback(link) })
      end
    end
  end

  # The next live link's button, else the one before, else the panel.
  def focus_fallback(link)
    at = live.index(link)
    [ live[at + 1], (live[at - 1] if at.positive?) ].compact.map { self.class.revoke_id(_1) }.push(self.class.dom_id(@upload)).join(" ")
  end

  def live = @live ||= @links.select { _1.state == :active }

  def state_badge(link)
    render LOOKS.fetch(link.state).badge(label: t("upload_links.states.#{link.state}"))
  end

  def meta(link)
    used = link.max_downloads ? t("upload_links.panel.used_of", used: link.downloads_count, max: link.max_downloads) : t("upload_links.panel.used", count: link.downloads_count)
    ends = link.expired? ? t("upload_links.panel.expired_on", date: l(link.expires_at, format: :short)) : t("upload_links.panel.expires_on", date: l(link.expires_at, format: :short))
    plain [ used, ends, t("upload_links.panel.made_by", name: link.profile.display_name, date: l(link.created_at.in_time_zone.to_date, format: :short)) ].join(" · ")
  end
end
