# frozen_string_literal: true

# /admin/emails: the mail this copy sends (Emails::Overview). One status
# card says whether mail goes out and what stops it otherwise, with the
# relay and what went against the budgets; then what waits and what
# couldn't go out, each counting its rows in its header and open while it
# holds any. The test mail is the top bar's while mail can go.
class Views::Admin::Emails::Index < Views::Base
  LOOKS = {
    sending: Components::StatusLook.new(tone: :good, icon: "fa-paper-plane"),
    paused: Components::StatusLook.new(tone: :warning, icon: "fa-pause"),
    off: Components::StatusLook.new(tone: :neutral, icon: "fa-power-off"),
    unconfigured: Components::StatusLook.new(tone: :critical, icon: "fa-triangle-exclamation")
  }.freeze

  def initialize(overview:)
    @overview = overview
  end

  def page_title = t("admin.emails.title")

  def navbar_controls
    return unless @overview.enabled?

    test = Components::Action.new(href: routes.admin_test_mail_path, icon: "fa-paper-plane", label: t("admin.emails.test.label"), method: :post)
    Components::PageControls.new(actions: [ test ])
  end

  def view_template
    div(class: "report-page emails") do
      render Components::PageHeader.new(title: t("admin.emails.title"))
      p(class: "report-hint") do
        plain t("admin.emails.hint")
        whitespace
        a(href: admin_settings_path) { t("admin.emails.settings_link") }
      end
      status
      waiting
      failed
    end
  end

  private

  def status
    look = LOOKS.fetch(@overview.state)
    render Components::Report::StatusCard.new(tone: look.tone, compact: true) do |card|
      card.head { render look.badge(label: t("admin.emails.states.#{@overview.state}")) }
      card.now { now }
      if @overview.pause&.reply
        p(class: "report-mono") { t("admin.emails.replied", reply: @overview.pause.reply) }
      end
      ul(class: "report-rows emails__facts") do
        fact(:relay) { relay }
        fact(:sender) { @overview.relay.from || t("admin.emails.not_set") }
        fact(:last_hour) { t("admin.emails.of_budget", count: @overview.used_this_hour, budget: @overview.hourly_budget) }
        fact(:last_day) { t("admin.emails.of_budget", count: @overview.used_today, budget: @overview.daily_budget) }
      end
    end
  end

  # What the state means, and what to do about it.
  def now
    case @overview.state
    when :paused
      plain t("admin.emails.now.paused", time: l(@overview.pause.ends_at, format: :hour_minute))
      whitespace
      plain t("admin.emails.problems.#{@overview.pause.problem}")
    when :unconfigured then plain t("admin.emails.unconfigured.#{@overview.relay.problem}")
    else plain t("admin.emails.now.#{@overview.state}")
    end
  end

  def relay
    relay = @overview.relay
    return plain(t("admin.emails.not_set")) if relay.host.nil?

    plain t("admin.emails.relay", host: relay.host, port: relay.port, tls: t("admin.emails.tls_modes.#{relay.tls}", default: relay.tls))
  end

  def fact(key, &)
    li do
      span(class: "emails__label") { t("admin.emails.facts.#{key}") }
      span(class: "emails__value", &)
    end
  end

  def waiting
    count = @overview.waiting_count
    render Components::Disclosure.new(key: "emails-waiting", title: t("admin.emails.waiting.title"), open: count.positive?,
                                      result: -> { plain count.to_s }) do
      rows(@overview.waiting, count, empty: t("admin.emails.waiting.empty"), icon: "fa-hourglass-half") do |row|
        row.sending? ? t("admin.emails.waiting.sending") : t("admin.emails.waiting.due", time: l(row.not_before, format: :short))
      end
    end
  end

  def failed
    count = @overview.failed_count
    render Components::Disclosure.new(key: "emails-failed", title: t("admin.emails.failed.title", days: Emails::Overview::FAILED_SINCE.in_days.to_i),
                                      open: count.positive?,
                                      result: -> { plain count.to_s }) do
      rows(@overview.failed, count, empty: t("admin.emails.failed.empty"), icon: "fa-circle-check") do |row|
        t("admin.emails.failed.when", time: l(row.updated_at, format: :short))
      end
    end
  end

  # A list of the outbox's rows, each saying when (the block) and why it
  # waits or failed, with what the relay answered; those past the first
  # few are counted.
  def rows(rows, count, empty:, icon:)
    return render(Components::EmptyState.new(icon: icon, message: empty)) if rows.empty?

    ul(class: "report-rows") do
      rows.each do |row|
        li(class: "emails__row") do
          p do
            strong { t("admin.emails.kinds.#{row.kind}") }
            span(class: "emails__who") { t("admin.emails.who", username: row.profile.username, household: row.profile.household.name) }
          end
          p(class: "emails__when") { yield row }
          p(class: "emails__reason") { t("admin.emails.reasons.#{row.reason}") } if row.reason
          p(class: "report-mono emails__detail") { row.detail } if row.detail
        end
      end
    end
    p(class: "report-hint") { t("admin.emails.more", count: count - rows.size) } if count > rows.size
  end
end
