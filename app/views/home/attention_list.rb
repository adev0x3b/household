# frozen_string_literal: true

# "Needs attention": the things to act on, each opening where it can be
# fixed (a modal, in place), a page at a time with the whole count in the
# heading. Renders nothing when there's nothing to do. An all-clear banner
# would just be noise on a dashboard people open often.
#
# An item about a day that passed unrecorded can be settled from here, the
# series' such days marked skipped in one press, and the footer settles
# every such item of the list at once. Both go through
# AttentionResolutionsController, out of the list's own frame, so the
# whole page draws itself again without them.
#
# Its page links (?attention_page=) reload its own frame and advance the
# URL, so a reload, or home refreshing after a change, stays on that page.
class Views::Home::AttentionList < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::ButtonTo

  PER_PAGE = 6
  FRAME = "stat-attention-list"
  HEADING = "stat-attention-heading"
  # An appointment has none here: it shows its own kind's, a visit's
  # stethoscope or a dinner's plate.
  ICONS = {
    missed_dose: "fa-pills",
    overdue_dose: "fa-clock",
    skipped_dose: "fa-forward",
    pending_lab_result: "fa-vial",
    supply_running_out: "fa-box-open",
    supply_low_stock: "fa-box-open",
    batch_expiring: "fa-hourglass-end",
    batch_expired: "fa-hourglass-end",
    critical_lab_value: "fa-flask",
    overdue_transaction: "fa-file-invoice-dollar",
    overdue_task: "fa-clipboard-list",
    meal_short_on_ingredients: "fa-utensils",
    unrecorded_meal: "fa-utensils"
  }.freeze

  # viewer: whoever reads the list, whose policies say which items they may
  # settle; none, and nothing can be. list: what names the page's list to
  # settle it whole: its section, which goes in the address as the page's
  # does, and its member.
  def initialize(items:, page: 1, viewer: nil, list: {})
    @items = items.to_a
    @page = page
    @viewer = viewer
    @list = list
  end

  def view_template
    return if @items.empty?

    section(class: "stat-attention", aria: { labelledby: HEADING }) do
      # Focusable from a script alone: it takes the focus when the row last
      # settled had no other row's button beside it.
      h2(id: HEADING, class: "stat-attention__title", tabindex: "-1") do
        render Components::Icon.new("fa-bell")
        span { t("statistics.attention.title") }
        span(class: "stat-attention__count") { @items.size.to_s }
      end
      turbo_frame_tag(FRAME) do
        ul(class: "stat-attention__list") { page.each { |item| entry(item) } }
        render Components::Pagination.new(collection: page, turbo_frame: FRAME, turbo_action: "advance", param_name: :attention_page,
                                          list: t("statistics.attention.title"))
        resolve_all_button if settled_here.any?
      end
    end
  end

  private

  # How many days of the series are in the same state, its newest shown:
  # "6 volte" beside a dose missed six times.
  def times(count)
    span(class: "stat-attention__times") { t("statistics.attention.times", count: count) } if count > 1
  end

  # A page past the last (items were dealt with since the link was made) is the last.
  def page
    @page_items ||= begin
      last = [ (@items.size.to_f / PER_PAGE).ceil, 1 ].max
      WillPaginate::Collection.create(@page.to_i.clamp(1, last), PER_PAGE, @items.size) { _1.replace(@items[_1.offset, _1.per_page]) }
    end
  end

  def entry(item)
    li(class: "stat-attention__item stat-attention__item--#{item.severity}") do
      link(item) do
        render Components::Icon.new(icon(item), class: "stat-attention__icon")
        span(class: "stat-attention__text") do
          strong do
            plain subject(item)
            times(item.count)
          end
          span(class: "stat-attention__detail") { detail(item) }
        end
        span(class: "is-sr-only") { t("statistics.attention.severity.#{item.severity}") }
        render Components::Icon.new("fa-chevron-right", class: "stat-attention__chevron")
      end
      resolve_button(item) if settled_here.include?(item)
    end
  end

  # The items of this page the viewer may settle, in the list's order.
  def settled_here = @settled_here ||= page.select { |item| resolvable?(item) }

  # Whether the viewer may settle the item here: its kind allows it, and
  # the day's policy lets them change it outright. A day the owner must OK
  # first gets no button, since the press promises to settle, not to ask.
  def resolvable?(item)
    return false unless item.resolvable && @viewer

    policy = Pundit.policy!(@viewer, item.occurrence)
    policy.change_status? && !policy.needs_approval?(:change_status?)
  end

  # The forms leave the list's frame, so the answer draws the whole page
  # again: the figures beside the list change with it.
  def resolve_button(item)
    label = t("statistics.attention.resolve", subject: subject(item))
    button_to(attention_resolutions_path, params: { event_id: item.occurrence.event_id }, class: "item-action",
                                          id: resolve_id(item), aria: { label: label }, title: label,
                                          data: { focus_fallback: focus_fallback(item) },
                                          form: { class: "stat-attention__resolve", data: { turbo_frame: "_top" } }) do
      render Components::Icon.new("fa-forward")
    end
  end

  def resolve_id(item) = "attention-#{item.kind.to_s.dasherize}-#{item.occurrence.event_id}-resolve"

  # Settled, the row leaves the list, so its button names where the focus
  # goes then: the next row's button, else the one before, else the heading.
  def focus_fallback(item)
    at = settled_here.index(item)
    after = settled_here[at + 1]
    before = settled_here[at - 1] if at.positive?
    [ after && resolve_id(after), before && resolve_id(before), HEADING ].compact.join(" ")
  end

  def resolve_all_button
    div(class: "stat-attention__footer") do
      button_to(attention_resolutions_path(section: @list[:section]), params: @list.except(:section).compact, class: "stat-attention__resolve-all",
                                                                      form: { data: { turbo_frame: "_top", turbo_confirm: t("statistics.attention.resolve_all_confirm") } }) do
        render Components::Icon.new("fa-forward")
        span { t("statistics.attention.resolve_all") }
      end
    end
  end

  # Opens what the item says it opens, in a modal, without leaving the page:
  # a day in its form, a supply in a new purchase of it (buying more), a
  # batch in its own purchase's form (to correct its date or what is left).
  # A report names no route, and an address alone can't say "buy more of
  # it", so the three are named here.
  def link(item, &)
    case item.opens
    when Occurrence then render(Views::Home::OccurrenceLink.new(occurrence: item.opens, class: "stat-attention__link"), &)
    when Supply then a(href: new_supply_purchase_path(item.opens), class: "stat-attention__link", data: { turbo_stream: true }, &)
    when SupplyPurchase then a(href: edit_supply_purchase_path(item.opens), class: "stat-attention__link", data: { turbo_stream: true }, &)
    end
  end

  def icon(item) = ICONS.fetch(item.kind) { Views::Calendar::Cards.icon_of(item.occurrence.event) }

  def subject(item) = item.subject.respond_to?(:name) ? item.subject.name : item.subject.to_s

  def detail(item)
    t("statistics.attention.kinds.#{item.kind}", date: item.date && l(item.date, format: :long), **item.words)
  end
end
