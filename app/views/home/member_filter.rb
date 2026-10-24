# frozen_string_literal: true

# "Whose data": everyone the viewer shares health records with, or just
# one of them. Only rendered when something is actually shared. Keeps the
# selected period when switching.
class Views::Home::MemberFilter < Views::Base
  def initialize(audience:, period:, url:)
    @audience = audience
    @period = period
    @url = url
  end

  def view_template
    return unless @audience.shared?

    render Components::AutoSubmitForm.new(url: @url, dom_id: "stat-member-filter", html_class: "stat-member-filter", turbo_action: "replace") do |form|
      @period.to_param.each { |name, value| input(type: "hidden", name: name.to_s, value: value) }
      label(for: "stat-member-filter_member_id", class: "stat-member-filter__label") do
        render Components::Icon.new("fa-user-group")
        span(class: "is-sr-only") { t("statistics.member_filter.label") }
      end
      form.select_field(name: "member_id", html_class: "stat-member-filter__select") do
        option(value: "", selected: !@audience.filtered?) { t("statistics.member_filter.everyone") }
        @audience.members.each do |profile|
          option(value: profile.id, selected: @audience.member&.id == profile.id) { member_label(profile) }
        end
      end
    end
  end

  private

  def member_label(profile)
    profile.id == @audience.viewer.id ? t("statistics.member_filter.me", name: profile.username) : profile.username
  end
end
