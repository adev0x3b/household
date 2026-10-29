# frozen_string_literal: true

# The navigation and nothing else: a drawer pulled up from the bottom on
# phones, a panel slid in from the left from a tablet up, with the wordmark
# at its head. The everyday pages, then the household's sections, each a page of
# the home dashboard with its own pages folded under it, its collections
# among them, then its people; the admin's and developer's pages folded
# at the bottom.
class Views::Layouts::Navbar::Sheet < Views::Base
  # everyday: the pages that head it (Components::NavItem); pending: what
  # waits for an answer on Links.
  def initialize(profile:, location:, everyday:, pending:)
    @profile = profile
    @location = location
    @everyday = everyday
    @pending = pending
  end

  def view_template
    # Inert until it is opened: off screen, it is out of the Tab order and of what a screen reader reads
    nav(id: Views::Layouts::Navbar::SHEET_ID, class: "navbar-sheet", inert: true, aria: { label: t("navbar.sheet.label") },
        data: { navbar_target: "menu" }) do
      # On phones the strip is pulled down to close the sheet (navbar_controller.js#dragStart)
      div(class: "navbar-sheet-handle", data: { navbar_target: "handle", action: "pointerdown->navbar#dragStart" }) do
        div(class: "navbar-handle-pill")
      end
      # From a tablet up the wordmark heads the panel, over the top bar's own
      a(href: root_path, class: "navbar-sheet-brand") do
        span(class: "navbar-logo-text") { t("app.name") }
      end

      div(class: "navbar-sheet-scroll") do
        render_links
      end
    end
  end

  private

  def render_links
    div(class: "navbar-links") do
      @everyday.each { |item| render_link(item) }

      render_caption(t("navbar.captions.sections"))
      render_group(:agenda, "fa-calendar-check", t("navbar.groups.agenda"), href: home_section_path(section: "agenda"), section: :agenda, links: [
                     collections(:agenda)
                   ])
      render_group(:healthcare, "fa-heart-pulse", t("navbar.groups.healthcare"), href: home_section_path(section: "healthcare"), section: :healthcare, links: [
                     Components::NavItem.new(href: collections_path(section: "healthcare"), icon: "fa-pills", label: t("navbar.links.therapies")),
                     Components::NavItem.new(href: analytes_path, icon: "fa-ruler", label: t("navbar.links.analytes")),
                     Components::NavItem.new(href: supplies_path, icon: "fa-box-open", label: t("navbar.links.supplies"))
                   ])
      render_group(:finance, "fa-sack-dollar", t("navbar.groups.finance"), href: home_section_path(section: "finance"), section: :finance, links: [
                     collections(:finance)
                   ])
      render_group(:pantry, "fa-kitchen-set", t("navbar.groups.pantry"), href: home_section_path(section: "pantry"), section: :pantry, links: [
                     collections(:pantry),
                     Components::NavItem.new(href: ingredients_path, icon: "fa-carrot", label: t("navbar.links.ingredients")),
                     Components::NavItem.new(href: recipes_path, icon: "fa-book-open", label: t("navbar.links.recipes")),
                     Components::NavItem.new(href: grocery_lists_path, icon: "fa-cart-shopping", label: t("navbar.links.grocery_lists"))
                   ])
      render_link(Components::NavItem.new(href: books_path, icon: "fa-book", label: t("navbar.links.bookshelf"), section: :bookshelf))
      render_link(Components::NavItem.new(href: uploads_path, icon: "fa-folder-open", label: t("navbar.links.files"), section: :files))

      render_caption(t("navbar.captions.people"))
      render_link(Components::NavItem.new(href: links_path, icon: "fa-link", label: t("navbar.links.links"), section: :links,
                                          badge: Views::Links::Badge.new(count: @pending)))

      render_admin
    end
  end

  def render_caption(text)
    p(class: "navbar-caption") { text }
  end

  # A section's collections, under its own name; Healthcare's are the
  # medical therapies, named as such.
  def collections(section)
    Components::NavItem.new(href: collections_path(section: section), icon: "fa-layer-group", label: t("navbar.links.collections"))
  end

  # The admin's pages (the assistant's settings, lexicon and evals among
  # them, and the errors and jobs dashboards) for admins. Nothing for the others.
  def render_admin
    return unless @profile&.admin?

    render_group(:admin, "fa-screwdriver-wrench", t("navbar.groups.admin"), links: [
                   Components::NavItem.new(href: admin_households_path, icon: "fa-city", label: t("navbar.links.households")),
                   Components::NavItem.new(href: admin_deployment_path, icon: "fa-rocket", label: t("navbar.links.deployment")),
                   Components::NavItem.new(href: admin_settings_path, icon: "fa-gear", label: t("navbar.links.settings")),
                   Components::NavItem.new(href: admin_emails_path, icon: "fa-envelope", label: t("navbar.links.emails")),
                   Components::NavItem.new(href: admin_errors_path, icon: "fa-bug", label: t("navbar.links.errors")),
                   Components::NavItem.new(href: admin_jobs_path, icon: "fa-list-check", label: t("navbar.links.jobs")),
                   Components::NavItem.new(href: assistant_settings_path, icon: "fa-sliders", label: t("navbar.links.assistant_settings")),
                   Components::NavItem.new(href: admin_lexicons_path, icon: "fa-language", label: t("navbar.links.lexicons")),
                   Components::NavItem.new(href: assistant_evals_path, icon: "fa-flask-vial", label: t("navbar.links.evals"))
                 ])
  end

  # extra: more classes, for a group's own link.
  def render_link(item, extra: nil)
    current = @location.current?(item.href, item.pages)
    a(href: item.href, class: [ "navbar-link", extra, ("is-current" if current), ("section--#{item.section}" if item.section) ],
      aria: { current: ("page" if current) }, data: { action: "click->navbar#hideMenu" }) do
      render Components::Icon.new(item.icon)
      span { item.label }
      render item.badge if item.badge
    end
  end

  # A folded list of links (Components::NavItem), open when it holds the
  # page you're on. With `href:` the header is that page's link and a toggle
  # beside it (a section and its sub-pages); without, the whole header
  # toggles (Admin). section: whose colour its icons take (see
  # _sections.scss); none, muted.
  def render_group(key, icon, label, links:, href: nil, section: nil)
    current = href && @location.current?(href)
    open = current || links.any? { |link| @location.current?(link.href, link.pages) }
    children_id = "navbar-group-#{key}"

    div(class: [ "navbar-group", ("section--#{section}" if section), ("is-open" if open) ], data: { controller: "navbar-group" }) do
      if href
        div(class: "navbar-group-header") do
          render_link(Components::NavItem.new(href: href, icon: icon, label: label), extra: "navbar-group-link")
          button(
            type: "button",
            class: "navbar-group-toggle",
            aria: { expanded: open.to_s, controls: children_id, label: t("navbar.groups.expand", group: label) },
            data: { navbar_group_target: "toggle", action: "click->navbar-group#toggle" },
          ) { chevron }
        end
      else
        button(
          type: "button",
          class: "navbar-group-header",
          aria: { expanded: open.to_s, controls: children_id },
          data: { navbar_group_target: "toggle", action: "click->navbar-group#toggle" },
        ) do
          render Components::Icon.new(icon)
          span(class: "navbar-group-label") { label }
          chevron
        end
      end

      # Folded, its links are out of sight, so they are out of reach too
      div(id: children_id, class: "navbar-group-children", inert: !open, data: { navbar_group_target: "children" }) do
        links.each { |link| render_link(link) }
      end
    end
  end

  def chevron = render Components::Icon.new("fa-chevron-down", class: "navbar-group-chevron")
end
