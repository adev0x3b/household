# frozen_string_literal: true

# /admin/households — every household, with how many people it holds and
# how many invitations are still waiting, a page at a time. A row opens the
# household's page; making one is the top bar's.
class Views::Admin::Households::Index < Views::Base
  def initialize(households:)
    @households = households
  end

  def page_title = t("admin.households.index.title")

  def navbar_controls
    new_household = Components::Action.new(href: routes.new_admin_household_path, icon: "fa-plus", label: t("admin.households.new.title"),
                                           turbo_stream: true)
    Components::PageControls.new(actions: [ new_household ])
  end

  def view_template
    div(class: "report-page household") do
      render Components::PageHeader.new(title: t("admin.households.index.title"))
      p(class: "report-hint") { hint }
      if @households.empty?
        render Components::EmptyState.new(icon: "fa-city", message: t("admin.households.index.empty"))
      else
        ul(class: "household__list") { @households.each { |household| row(household) } }
        render Components::Pagination.new(collection: @households)
      end
    end
  end

  private

  def hint
    size = ::Platform.household_size
    return t("admin.households.index.hint") if size.nil?

    t("admin.households.index.hint_with_size", max: size)
  end

  def row(household)
    joined, waiting = household.profiles.partition { |profile| !profile.invitation_pending? }
    li(class: "household__row") do
      render Components::Icon.new("fa-house-chimney", class: "household__icon")
      div(class: "household__who") do
        a(href: admin_household_path(household), class: "household__name") { household.name }
        p(class: "household__facts") do
          plain t("admin.households.index.members", count: joined.size)
          span(class: "household__fact") { t("admin.households.index.waiting", count: waiting.size) } if waiting.any?
          span(class: "household__fact") { t("admin.households.index.since", date: l(household.created_at.in_time_zone.to_date, format: :long)) }
        end
      end
    end
  end
end
