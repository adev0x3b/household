# frozen_string_literal: true

# A record more than one person can edit at once: its owner and the
# housemates it is shared with or linked to. Rails checks its `lock_version`
# on every update and refuses one made from an older copy
# (ActiveRecord::StaleObjectError), and `updated_by` says who saved it last.
#
#   # recipe_params carries the lock_version the form was drawn with
#   typed = EditedTogether::TypedFields.new(params[:typed_fields], recipe_params, under: "recipe")
#   if recipe.edit_as(current_profile, typed:) { recipe.update(recipe_params) }
module EditedTogether
  extend ActiveSupport::Concern

  included do
    belongs_to :updated_by, class_name: "Profile", optional: true
    before_save :name_the_editor
  end

  class_methods do
    # Writes columns that aren't an edit of the rows (when a conversation's
    # last message came, what a done day keeps), so their version stays and
    # a form open on one still saves. update_all would move it on.
    def update_all_keeping_version(updates)
      update_all(updates.merge(locking_column => arel_table[locking_column]))
    end
  end

  # What the form whose save was refused says was typed in it, so that it
  # comes back saying so again (Components::Form).
  attr_accessor :typed_fields

  # A form's save of this record by `profile`, against the version the form
  # was drawn with: what the block answers, or false when someone saved the
  # record since, with the reason on it. The form then shows what was typed
  # in it over what the other person saved, or, when it didn't say what was
  # typed (`typed`, EditedTogether::TypedFields), everything as it was sent.
  # Another record's crossed save is no answer of this form's, and goes on
  # up.
  def edit_as(profile, typed: nil)
    edited_by(profile)
    # Written even when nothing of its own changed (a recipe whose lines
    # alone did), so that its version is still checked and moved on.
    updated_by_id_will_change!
    yield
  rescue ActiveRecord::StaleObjectError => e
    raise unless e.record.equal?(self)

    typed_over_theirs(typed) if typed&.told?
    changed_meanwhile!(profile)
    false
  end

  # The row as the other person saved it, its lists included, with what
  # the form says was typed laid over it.
  def typed_over_theirs(typed)
    reload
    assign_attributes(typed.attributes)
    self.typed_fields = typed
  end

  # update_all_keeping_version for this record, written onto this copy too.
  def update_columns_keeping_version(attributes)
    self.class.where(id: id).update_all_keeping_version(attributes)
    assign_attributes(attributes)
    clear_attribute_changes(attributes.keys.map(&:to_s))
  end

  # Names who is saving through this copy, for each of its writes: a save
  # that changes the day and then its status is one person's. The name is
  # written as the copy saves, so a press that locks the row first, which
  # a copy with unsaved changes can't, names its person too.
  def edited_by(profile)
    @editor = profile
    self
  end

  # Moves the version on because something it holds changed (a day's
  # details, a series' times, a lab value), as touch would but whatever
  # version this copy was read at: the change is to those rows, not an edit
  # made from an older copy of this one. Touching later, through a copy,
  # would be refused once another copy of the row had saved in the same
  # transaction. Who saved it last stays, since the holder changed with it.
  def mark_changed!
    now = Time.current
    self.class.where(id: id).update_all(updated_at: now)
    self.lock_version += 1
    self.updated_at = now
    clear_attribute_changes(%w[lock_version updated_at])
  end

  # After a refused update: catches up with the row and says so on the
  # record, for `viewer`, whose form keeps what was typed.
  def changed_meanwhile!(viewer)
    catch_up!
    if updated_by_id == viewer.id
      errors.add(:base, :changed_meanwhile_by_you)
    elsif updated_by
      errors.add(:base, :changed_meanwhile_by, name: updated_by.display_name)
    else
      errors.add(:base, :changed_meanwhile)
    end
    self
  end

  # Takes the version and who saved it from the row, keeping everything
  # else this copy holds, so that saving it again replaces the other change
  # knowingly. A row that is gone was deleted meanwhile, which is a
  # different refusal.
  def catch_up!
    version, editor_id = self.class.where(id: id).pick(:lock_version, :updated_by_id)
    raise ActiveRecord::RecordNotFound.new("#{self.class.name} #{id} was deleted meanwhile", self.class.name, :id, id) if version.nil?

    self.lock_version = version
    self.updated_by_id = editor_id
    clear_attribute_changes(%w[lock_version updated_by_id])
    self
  end

  private

  # A copy nobody was named on (a job's, a press that names nobody) leaves
  # nobody named, rather than the person who saved before it.
  def name_the_editor
    self.updated_by = @editor
  end
end
