# frozen_string_literal: true

# What a notification says, in the current language: its title, the line
# under it, and the kind of its toast. The bell's row, the toast and the
# push all read it here, so a notification is worded once; the model keeps
# only what happened (its kind, subject and data), as Destination keeps
# where it leads.
#
#   wording = Notifications::Wording.new(notification)
#   wording.title       # => "Bob shared a recipe with you"
#   wording.detail      # => "Roast chicken"
#   wording.toast_kind  # => :notice
class Notifications::Wording
  # These kinds are worded per something in them: a share per what was
  # shared (kinds.shared.recipe), a message per kind of conversation
  # (kinds.message_received.direct), a linked housemate's request per what
  # it asks (kinds.approval_requested.update).
  SHARE_KINDS = %w[shared unshared].freeze
  APPROVAL_KINDS = %w[approval_requested approval_approved approval_declined approval_failed].freeze

  # What a kind's words may quote from its data as it was saved.
  QUOTED = %w[language model name passed total version].freeze

  def initialize(notification)
    @notification = notification
  end

  def title
    I18n.t("notifications.kinds.#{title_key}", **variables)
  end

  # What a job said, why it ended as it did, why a request couldn't be done,
  # a score, when something is due, or else the subject's name as it was
  # when the notification was made.
  def detail
    data["detail"].presence ||
      data["outcome"].presence&.then { I18n.t("notifications.outcomes.#{_1}") } ||
      data["failure"].presence&.then { I18n.t("links.approvals.failures.#{_1}") } ||
      I18n.t("notifications.details.#{kind}", **variables, default: nil) ||
      @notification.subject_title
  end

  def toast_kind
    if @notification.failure? then :alert
    elsif @notification.success? then :success
    else :notice
    end
  end

  private

  def kind = @notification.kind
  def data = @notification.data

  def title_key
    if SHARE_KINDS.include?(kind) then "#{kind}.#{shared_thing}"
    elsif @notification.message_received? then "#{kind}.#{data["scope"].presence || "household"}"
    elsif APPROVAL_KINDS.include?(kind) then "#{kind}.#{data["verb"].presence || "update"}"
    else kind
    end
  end

  # A collection is named as its section names it (a therapy in
  # Healthcare), and plainly once it is gone.
  def shared_thing
    name = @notification.subject_type.to_s.underscore
    name == "collection" ? "collection.#{@notification.subject.try(:section) || "other"}" : name
  end

  def variables
    { actor: actor_name, title: @notification.subject_title, when: due_label, thing: thing, what: what }
      .merge(QUOTED.to_h { [ _1.to_sym, data[_1] ] })
  end

  def actor_name
    actor = @notification.actor
    actor&.display_name || I18n.t("notifications.someone")
  end

  # The admin's press, in the reader's words: "The deploy to staging".
  def what
    return unless data.key?("action")

    destination = I18n.t("admin.deployment.destinations.#{data["destination"]}", default: data["destination"])
    I18n.t("notifications.deployment.what.#{data["action"]}", destination: destination, ref: data["ref"], version: data["version"])
  end

  # The kind of item a linked housemate's request is about: "task".
  def thing
    return unless data.key?("type")

    I18n.t("links.things.#{data["type"].to_s.underscore}", default: I18n.t("links.things.item"))
  end

  # "Thu 9 Oct, 14:00", or the day alone when the thing has no time of day,
  # on the recipient's clock whoever is reading.
  def due_label
    return if data["due_at"].blank?

    due_at = Time.zone.parse(data["due_at"])
    format = data["timed"] ? "reminders.formats.day_time" : "reminders.formats.day"
    I18n.l(due_at.in_time_zone(@notification.profile.zone), format: I18n.t(format))
  end
end
