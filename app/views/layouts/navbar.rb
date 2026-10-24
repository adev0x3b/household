# frozen_string_literal: true

# The app's chrome on every signed-in page: the top bar
# (Views::Layouts::Navbar::Topbar: the wordmark, the page's controls, the bell,
# the account menu), the navigation (Views::Layouts::Navbar::Sheet: a drawer
# pulled up from the bottom on phones, a panel slid in from the left from
# a tablet up, opened by the bar's burger), and on phones the bottom bar
# (Views::Layouts::Navbar::BottomBar) with the everyday pages and the Menu tab.
# navbar_controller.js opens and closes the drawer from either.
class Views::Layouts::Navbar < Views::Base
  SHEET_ID = "navbar-sheet"

  # facts: the counts and devices the bar shows (Navbar::Facts, read by the
  # controller). current_path: the request's, to mark the link you're on
  # (and open its group).
  def initialize(profile:, facts:, page_controls: nil, current_path: nil)
    @profile = profile
    @facts = facts
    @page_controls = page_controls
    @current_path = current_path
  end

  def view_template
    location = ::Navbar::Location.new(@current_path, root: root_path)

    render Views::Layouts::Navbar::Topbar.new(profile: @profile, location: location, page_controls: @page_controls,
                                              unread_notifications: @facts.unread_notifications, push_digests: @facts.push_digests)
    div(class: "navbar-backdrop", data: { navbar_target: "overlay", action: "click->navbar#hideMenu" })
    render Views::Layouts::Navbar::Sheet.new(profile: @profile, location: location, everyday: everyday, pending: @facts.pending_links)
    render Views::Layouts::Navbar::BottomBar.new(location: location, everyday: everyday, pending: @facts.pending_links)
  end

  private

  # The pages used every day, which head the drawer and fill the phone's
  # bottom bar. Each bar draws its own copy, so each gets its own list.
  def everyday
    [
      Components::NavItem.new(href: root_path, icon: "fa-house", label: t("navbar.links.home")),
      Components::NavItem.new(href: calendar_path, icon: "fa-calendar-days", label: t("navbar.links.calendar")),
      (assistant if Platform.assistant?),
      Components::NavItem.new(href: conversations_path, icon: "fa-comment-dots", label: t("navbar.links.messages"), section: :messages,
                              badge: Views::Conversations::Badge.new(count: @facts.unread_messages))
    ].compact
  end

  def assistant
    Components::NavItem.new(href: assistant_path, icon: "fa-feather-pointed", label: t("navbar.links.assistant"),
                            pages: assistant_chats_path, section: :assistant)
  end
end
