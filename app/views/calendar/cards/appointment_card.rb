# frozen_string_literal: true

# An appointment's day: its kind's icon, title, time, who it's with and
# where. Its section follows its kind (a medical visit is Healthcare, an
# interview Agenda): the card takes that section's colour.
class Views::Calendar::Cards::AppointmentCard < Views::Calendar::Cards::Base
  KIND_ICONS = {
    "medical" => "fa-user-doctor", "work" => "fa-briefcase", "social" => "fa-user-group",
    "personal" => "fa-calendar-check", "other" => "fa-calendar"
  }.freeze

  # A new appointment starts as a visit to a doctor.
  def self.icon = kind_icon(Appointment::Kind.default)
  def self.icon_of(event) = kind_icon(event.kind)
  def self.kind_icon(kind) = KIND_ICONS.fetch(kind.name)

  private

  def prefix = "appointment-card"

  def content
    div(class: "appointment-card__content") do
      div(class: "appointment-card__header") do
        render Components::Icon.new(self.class.icon_of(@event), class: "appointment-card__kind-icon", title: @event.kind.label)
        title_link
      end

      detail_row
      outcome
      attached_costs
    end
  end

  def detail_row
    parts = [ @occurrence.formatted_start_time, details.counterpart, @occurrence.location ].compact_blank
    return if parts.empty?

    span(class: "appointment-card__detail") { parts.join(" · ") }
  end
end
