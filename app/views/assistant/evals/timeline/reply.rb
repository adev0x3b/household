# frozen_string_literal: true

# The assistant's reply, with the model's thinking folded away.
class Views::Assistant::Evals::Timeline::Reply < Views::Assistant::Evals::Timeline::Entry
  def view_template
    reply = ::Assistant::ModelReply.new(@event["text"])
    li(id: "eval-reply-#{@event["turn"]}", class: "eval-tl eval-tl--reply") do
      span(class: "eval-tl__who") do
        render Components::Icon.new("fa-feather-pointed")
        plain " #{t("assistant.evals.live.assistant")}"
      end
      if reply.thinking.present?
        details(class: "eval-tl__thinking") do
          summary { t("assistant.evals.live.thinking") }
          p { reply.thinking }
        end
      end
      p(class: "eval-tl__reply") { reply.answer } if reply.answer.present?
    end
  end
end
