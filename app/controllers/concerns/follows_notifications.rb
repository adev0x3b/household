# frozen_string_literal: true

# Going where a notification points, once it is opened or read. One whose
# subject is gone leads nowhere: back where the reader was, or home.
module FollowsNotifications
  extend ActiveSupport::Concern

  private

  def follow(notification, status: :found)
    if (path = Notifications::Destination.new(notification).path)
      redirect_to path, status: status
    else
      redirect_back_or_to root_path, status: status
    end
  end
end
