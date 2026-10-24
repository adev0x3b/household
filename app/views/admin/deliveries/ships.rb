# frozen_string_literal: true

# The commits a press would put somewhere (what main gains from a merge,
# what a destination gains from a deploy or a release), newest first, the
# oldest folded into "and N more" past SHOWN; or that nothing ships.
class Views::Admin::Deliveries::Ships < Views::Base
  SHOWN = 8

  def initialize(commits)
    @commits = commits
  end

  def view_template
    if @commits.empty?
      p(class: "report-hint") { t("admin.deployment.modals.ships.none") }
      return
    end

    p(class: "deployment-modal__line") { t("admin.deployment.modals.ships.count", count: @commits.size) }
    ul(class: "report-rows deployment-modal__commits") do
      @commits.last(SHOWN).reverse_each do |commit|
        li do
          span(class: "report-mono") { commit.short }
          whitespace
          span { commit.title }
        end
      end
      li(class: "report-hint") { t("admin.deployment.modals.ships.more", count: @commits.size - SHOWN) } if @commits.size > SHOWN
    end
  end
end
