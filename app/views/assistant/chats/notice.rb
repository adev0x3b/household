# frozen_string_literal: true

class Views::Assistant::Chats::Notice < Views::Base
  def initialize(kind:, text:)
    @kind = kind
    @text = text
  end

  def view_template
    div(class: "assistant-notice assistant-notice--#{@kind}") do
      render Components::Icon.new(@kind == :error ? "fa-circle-exclamation" : "fa-circle-info")
      span { @text }
    end
  end
end
