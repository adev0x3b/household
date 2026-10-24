# frozen_string_literal: true

# What the assistant is changing, grouped by what the user asked for. Each
# row has its edit button; the footer holds what acts on the whole set:
# Apply for a deletion, a possible duplicate or a change someone else will
# see, Cancel, and Undo once saved.
class Views::Assistant::Chats::ChangeSetCard < Views::Base
  include Phlex::Rails::Helpers::ButtonTo
  include Views::Calendar::DayPaths

  STATUS_ICONS = { "ready" => "fa-circle-check", "applied" => "fa-circle-check", "asked" => "fa-hourglass-half", "missing" => "fa-circle-question",
                   "ambiguous" => "fa-circle-question", "confirm" => "fa-hand", "invalid" => "fa-triangle-exclamation" }.freeze

  def self.dom_id(set) = "assistant-change-set-#{set.id}"

  # targets: what each row's edit button opens (Assistant::ChangeSets::RowTargets).
  def initialize(change_set:, targets:)
    @set = change_set
    @targets = targets
  end

  def view_template
    div(id: self.class.dom_id(@set), class: "assistant-change-set assistant-change-set--#{@set.status}") do
      p(class: "assistant-change-set__status") do
        render Components::Icon.new(@set.applied? ? "fa-floppy-disk" : "fa-list-check")
        span { t("assistant.change_sets.status.#{@set.status}") }
      end
      rows
      notes if @set.in_progress?
      actions
    end
  end

  private

  # Why the set waits: deleting can't be undone, and someone else will
  # see the change.
  def notes
    p(class: "assistant-change-set__note") { t("assistant.change_sets.not_undoable") } if @set.deletes?
    names = @set.seen_by
    p(class: "assistant-change-set__note") { t("assistant.change_sets.seen_by", names: names.to_sentence, count: names.size) } if names.any?
  end

  def rows
    grouped = @set.display.group_by { |row| row["intent"] }
    ul(class: "assistant-change-set__list") do
      grouped.each do |intent, ops|
        li(class: "assistant-change-set__intent") do
          p(class: "assistant-change-set__asked") { @set.intents[intent.to_i].to_s } if intent && @set.intents[intent.to_i]
          ops.each { |row| op_row(row) }
        end
      end
    end
  end

  def op_row(row)
    status = @set.undone? || @set.cancelled? || @set.expired? ? nil : row["status"]
    p(class: "assistant-change-set__op#{" assistant-change-set__op--#{status}" if status}") do
      render Components::Icon.new(STATUS_ICONS.fetch(status.to_s, "fa-circle"))
      span { row["summary"] }
      span(class: "assistant-change-set__op-status") { t("assistant.change_sets.op_status.#{status}") } if status && status != "applied"
      edit_action(row)
    end
  end

  # Apply puts the set's application there, Undo takes it away, and Cancel
  # drops a set still in progress.
  def actions
    return unless @set.awaiting_confirmation? || @set.open? || (@set.applied? && @set.undoable)

    div(class: "assistant-change-set__actions") do
      if @set.awaiting_confirmation?
        set_button(:apply, assistant_change_set_application_path(@set), :post, @set.deletes? ? "modal__btn--danger" : "modal__btn--primary")
        set_button(:cancel, assistant_change_set_path(@set), :delete, "modal__btn--cancel")
      elsif @set.open?
        set_button(:cancel, assistant_change_set_path(@set), :delete, "modal__btn--cancel")
      else
        set_button(:undo, assistant_change_set_application_path(@set), :delete, "modal__btn--cancel")
      end
    end
  end

  # A saved row opens its record's edit modal (a day's is its series'); a
  # row still in progress opens the create modal of its draft.
  def edit_action(row)
    target = @targets.for(@set, row)
    return unless target

    href = edit_path(target)
    render Components::ItemAction.new(href: href, icon: "fa-pen", turbo_stream: true,
                                      label: t("assistant.change_sets.buttons.#{target.record ? "edit" : "review"}_thing", thing: t("assistant.types.#{target.type}")))
  end

  def edit_path(target)
    return review_assistant_change_set_path(@set, draft: target.draft) unless target.record
    return day_form_path(target.record) if target.record.is_a?(Occurrence)

    edit_polymorphic_path(target.record)
  end

  def set_button(action, path, method, style)
    label = t("assistant.change_sets.buttons.#{action}#{"_delete" if action == :apply && @set.deletes?}")
    button_to(label, path, method: method, class: "modal__btn assistant-change-set__btn #{style}", form: { data: { turbo_stream: true } })
  end
end
