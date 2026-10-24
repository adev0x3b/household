# frozen_string_literal: true

# What a notification says to its reader (Notifications::Wording),
# for tests that assert what someone was told.
module NotificationWording
  def wording_of(notification) = Notifications::Wording.new(notification)
end
