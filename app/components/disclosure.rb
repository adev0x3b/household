# frozen_string_literal: true

# A part of a page that folds, with its result in its header ("12 of 12
# passed", a status pill), so the page reads without opening anything.
# `open:` is the default the page picks (open when the part failed, runs or
# waits for the reader). `key:` keeps the reader's own choice across the
# polls that draw the page again (disclosure_controller.js); key it by the
# record, so a new run starts from the page's defaults.
#
#   render Components::Disclosure.new(key: "lexicon-42-steps", title: t("…"), open: failed,
#                                     result: -> { plain t("…", done: 4, total: 5) }) do
#     ol { … }
#   end
class Components::Disclosure < Components::Base
  def initialize(key:, title:, open: false, result: nil, id: nil)
    @key = key
    @title = title
    @open = open
    @result = result
    @id = id
  end

  def view_template(&)
    details(id: @id, class: "disclosure", open: @open, data: { controller: "disclosure", disclosure_key_value: @key }) do
      summary(class: "disclosure__summary", data: { action: "click->disclosure#remember" }) do
        render Components::Icon.new("fa-chevron-right", class: "disclosure__chevron")
        h2(class: "disclosure__title") { @title }
        span(class: "disclosure__result") { render @result } if @result
      end
      div(class: "disclosure__body", &)
    end
  end
end
