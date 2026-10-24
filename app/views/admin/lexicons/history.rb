# frozen_string_literal: true

# The language's earlier imports, ten to a page, in a frame of their own so
# paging swaps the list alone; an import's link opens its page.
class Views::Admin::Lexicons::History < Views::Admin::Lexicons::Part
  include Phlex::Rails::Helpers::TurboFrameTag

  # history: a page of the language's imports (will_paginate); import: the one shown.
  def initialize(language:, import:, history:)
    @language = language
    @import = import
    @history = history
  end

  def render? = @history.total_entries > 1

  def view_template
    turbo_frame_tag("lexicon-history", target: "_top") do
      section(@import&.id || @language.code, "history", title: t("admin.lexicons.show.history"), open: false,
                                                        result: -> { plain @history.total_entries.to_s }) do
        list
        render Components::Pagination.new(collection: @history, turbo_frame: "lexicon-history", turbo_action: "advance", param_name: :history_page)
      end
    end
  end

  private

  def list
    ul(class: "lexicons__history") do
      @history.each do |import|
        li(class: ("is-current" if import == @import)) do
          a(href: admin_lexicon_path(@language.code, import: import.id)) { l(import.created_at, format: :short) }
          whitespace
          render Views::Admin::Lexicons::StatusBadge.new(status: import.status)
          span { " #{t("admin.lexicons.failed_at", step: t("admin.lexicons.steps.#{import.failed_step}"))}" } if import.failed?
        end
      end
    end
  end
end
