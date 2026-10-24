# frozen_string_literal: true

# The assistant's own pages — its chats, messages, change sets and photos —
# exist only where the installation has the assistant on (Platform.assistant?;
# ASSISTANT=off): elsewhere they are a 404, like any page that isn't there,
# and the navbar doesn't offer them. The admin's pages, its settings and
# evals, stay, so it can be set up before it is turned on.
module AssistantEnabled
  extend ActiveSupport::Concern

  included do
    before_action :assistant_enabled!
  end

  private

  def assistant_enabled!
    raise ActionController::RoutingError, "The assistant is off on this installation" unless Platform.assistant?
  end
end
