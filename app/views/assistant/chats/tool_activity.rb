# frozen_string_literal: true

# A line under the chat for each thing the assistant did, in
# everyday words ("Saved an appointment"), never a tool's name.
class Views::Assistant::Chats::ToolActivity < Views::Base
  # Only reads have their own line: a change that worked shows as its card,
  # and a write tool falls back to the generic line, seen only on a failure.
  ICONS = { "search_records" => "fa-magnifying-glass", "get_record" => "fa-eye" }.freeze

  def initialize(tool_name:, arguments:, result:)
    @tool = tool_name.to_s
    @arguments = arguments.to_h.transform_keys(&:to_s)
    @result = result.to_h
  end

  def view_template
    div(class: "assistant-activity#{" assistant-activity--failed" unless ok?}") do
      render Components::Icon.new(ok? ? ICONS.fetch(@tool, "fa-gear") : "fa-triangle-exclamation")
      span { ok? ? label : t("assistant.activity.failed", action: label) }
    end
  end

  private

  def ok? = @result[:ok] == true
  def data = @result[:data].is_a?(Hash) ? @result[:data] : {}

  # The model may name a type the app doesn't have; its line then says "a record".
  def type_label
    resource = ::Assistant::Resources.lookup(@arguments["type"])
    resource ? t("assistant.types.#{resource.key}") : t("assistant.types.record")
  end

  # The tool says how its line reads; a tool the app no longer has is "other".
  def label
    tool = ::Assistant::BookkeeperAgent.tool_named(@tool)
    t("assistant.activity.#{tool ? tool.activity_key : "other"}", type: type_label)
  end
end
