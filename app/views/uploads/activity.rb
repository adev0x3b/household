# frozen_string_literal: true

# What happened to a file, newest first: uploaded, shared, downloaded, a
# link made, used, refused… For its owner. A link's use shows where it
# came from, since there is nobody to name. `older`: how many entries came
# before these, which the trail counts rather than lists.
class Views::Uploads::Activity < Views::Base
  ICONS = { "uploaded" => "fa-cloud-arrow-up", "shared" => "fa-share-nodes", "unshared" => "fa-user-slash", "downloaded" => "fa-download",
            "link_created" => "fa-link", "link_revoked" => "fa-link-slash", "link_downloaded" => "fa-globe", "link_refused" => "fa-ban", "link_locked" => "fa-lock" }.freeze

  def initialize(entries:, older: 0)
    @entries = entries
    @older = older
  end

  def view_template
    return render Components::EmptyState.new(icon: "fa-clock-rotate-left", message: t("uploads.activity.empty")) if @entries.empty?

    ul(class: "upload-activity") do
      @entries.each do |entry|
        li(class: "upload-activity__entry") do
          render Components::Icon.new(ICONS.fetch(entry.action), class: "upload-activity__icon")
          span(class: "upload-activity__text") { wording(entry) }
          time(class: "upload-activity__time", datetime: entry.created_at.iso8601) { l(entry.created_at, format: :short) }
        end
      end
    end
    p(class: "upload-activity__older") { t("uploads.activity.older", count: @older) } if @older.positive?
  end

  private

  def wording(entry)
    who = entry.profile&.display_name || t("notifications.someone")
    t("uploads.activity.#{entry.action}", who: who, with: entry.data["with"], ip: entry.ip || "?", wrong_passwords: entry.data["wrong_passwords"],
                                          reason: (t("uploads.activity.reasons.#{entry.data["reason"]}", default: "") if entry.data["reason"]))
  end
end
