# frozen_string_literal: true

# The phone's bottom navigation bar (gone from a tablet up, where the top
# bar's burger opens the navigation): the everyday pages, then Menu, which
# opens the drawer and counts what waits for an answer on Links. The page
# you're on is marked.
class Views::Layouts::Navbar::BottomBar < Views::Base
  # everyday: the pages it lists (Components::NavItem); pending: what waits
  # for an answer on Links.
  def initialize(location:, everyday:, pending:)
    @location = location
    @everyday = everyday
    @pending = pending
  end

  def view_template
    nav(class: "bottom-nav", aria: { label: t("navbar.bottom.label") }, data: { navbar_target: "behind" }) do
      @everyday.each { |item| tab(item) }
      menu
    end
  end

  private

  def tab(item)
    current = @location.current?(item.href, item.pages)
    a(href: item.href, class: [ "bottom-nav__item", ("is-current" if current), ("section--#{item.section}" if item.section) ],
      aria: { current: ("page" if current) }) do
      span(class: "bottom-nav__icon") do
        render Components::Icon.new(item.icon)
        render item.badge if item.badge
      end
      span(class: "bottom-nav__label") { item.label }
    end
  end

  def menu
    button(
      type: "button",
      class: "bottom-nav__item bottom-nav__menu",
      aria: { expanded: "false", controls: Views::Layouts::Navbar::SHEET_ID },
      data: { navbar_target: "toggler", action: "navbar#toggle" },
    ) do
      span(class: "bottom-nav__icon") do
        render Components::Icon.new("fa-bars")
        render Views::Links::Badge.new(count: @pending)
      end
      span(class: "bottom-nav__label") { t("navbar.menu") }
    end
  end
end
