# frozen_string_literal: true

# A book's status as a pill: an icon and a label, never color alone. The
# status pills on the shelf and the book's page take the same icons.
class Views::Books::StatusBadge < Views::Base
  LOOKS = {
    "want_to_read" => Components::StatusLook.new(tone: :neutral, icon: "fa-bookmark"),
    "reading" => Components::StatusLook.new(tone: :neutral, icon: "fa-book-open-reader"),
    "read" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "dropped" => Components::StatusLook.new(tone: :warning, icon: "fa-ban")
  }.freeze

  def self.icon(status) = LOOKS.fetch(status.to_s).icon

  def initialize(status:)
    @status = status.to_s
  end

  def view_template
    render LOOKS.fetch(@status).badge(label: t("books.status.#{@status}"))
  end
end
