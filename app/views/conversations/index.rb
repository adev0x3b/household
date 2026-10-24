# frozen_string_literal: true

# The household's conversations: its own first, then one per housemate —
# those already begun, newest news first, then the people not yet written
# to. Each row is replaced live (Conversations::Broadcaster) as messages
# come and go.
class Views::Conversations::Index < Views::Base
  # summaries: what the rows say, read for all of them at once (Conversations::Summaries).
  def initialize(household_conversation:, direct:, housemates_without:, summaries:, viewer:)
    @household_conversation = household_conversation
    @direct = direct
    @housemates_without = housemates_without
    @summaries = summaries
    @viewer = viewer
  end

  def page_title = t("conversations.index.title")

  def view_template
    div(class: "conversation-list section--messages") do
      render Components::PageHeader.new(title: t("conversations.index.title"))

      render Views::Conversations::Row.new(conversation: @household_conversation, viewer: @viewer, summaries: @summaries)

      h2(class: "conversation-list__heading") { t("conversations.index.people") }
      if @direct.empty? && @housemates_without.empty?
        render Components::EmptyState.new(icon: "fa-user-group", message: t("conversations.index.alone"))
      else
        @direct.each { |conversation| render Views::Conversations::Row.new(conversation: conversation, viewer: @viewer, summaries: @summaries) }
        @housemates_without.each { |housemate| render Views::Conversations::Row.new(housemate: housemate, viewer: @viewer) }
      end
    end
  end
end
