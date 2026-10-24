# frozen_string_literal: true

# What every policy starts from: nobody may do anything until a policy says
# otherwise, so an action a policy forgets to answer is refused rather than
# allowed. The form actions follow the ones that save them, as Rails pairs
# them: whoever may create may open the new form, whoever may update may open
# the edit form.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  # The records a user may see in a list. There is no safe default for a
  # list, so a policy that is asked for one must say which.
  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class} doesn't say which records a list shows"
    end

    private

    attr_reader :user, :scope
  end

  private

  # Whose the record is: the user's own (its profile), or shared with them
  # (Shareable#shared_with?; never, for what can't be shared). A record that
  # belongs to something else answers through it: its policy names it in
  # owning_record (a grocery list's item, its list).
  def owner? = owning_record&.profile_id == user.id
  def shared? = owning_record.respond_to?(:shared_with?) && owning_record.shared_with?(user)
  def owning_record = record
end
