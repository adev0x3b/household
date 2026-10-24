# frozen_string_literal: true

# What's wrong with a scenario when it is saved: a critical notice at the
# top of the form, one line each. (A Try says it in toasts.)
class Views::Assistant::Evals::Errors < Views::Base
  def initialize(messages:)
    @messages = messages
  end

  def view_template
    return if @messages.empty?

    render Components::Notice.new(tone: :critical) do
      ul(class: "eval-errors") { @messages.each { |message| li { message } } }
    end
  end
end
