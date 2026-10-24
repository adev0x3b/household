# frozen_string_literal: true

# A run of bubbles: the thread's, or an older page's put above it.
class Views::Conversations::Bubbles < Views::Base
  def initialize(messages:, viewer:)
    @messages = messages
    @viewer = viewer
  end

  def view_template
    @messages.each { |message| render Views::Conversations::Bubble.new(message: message, viewer: @viewer) }
  end
end
