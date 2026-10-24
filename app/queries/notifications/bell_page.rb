# frozen_string_literal: true

# One page of a person's bell: the newest notifications, or, after one of
# them, the ones before it, and whether older ones follow. A row more than
# the page is read to know that.
class Notifications::BellPage
  SIZE = 30

  # notifications: the person's own (the policy's scope); after: the last
  # row shown, for the page under it.
  def initialize(notifications, after: nil)
    @notifications = notifications
    @after = after
  end

  def rows = page.first(SIZE)
  def more? = page.size > SIZE

  private

  def page
    @page ||= begin
      scope = @notifications.recent_first.includes(:actor, :subject)
      scope = scope.older_than(@after) if @after
      scope.limit(SIZE + 1).to_a
    end
  end
end
