# frozen_string_literal: true

module Links
  # Keeps a person's open pages in step with their links, over their
  # notifications stream (`turbo_stream_from profile, :notifications`, on
  # every page): the navbar button's count, and the Links page's sections
  # when it is the one open (replacing an element a page doesn't have does
  # nothing).
  #
  # DOM contract: .links-badge (Views::Links::Badge: every copy at once,
  # the drawer's Links row and the phone's Menu tab), #links-page
  # (Views::Links::Sections).
  class Broadcaster < ApplicationBroadcaster
    # Each of `profiles` — both people of a link, usually — read together.
    def self.changed(*profiles)
      quietly do
        counts = Pending.counts_for(profiles)
        page = Page.new(profiles)
        profiles.each do |profile|
          as(profile) do
            stream_to([ profile, :notifications ], :replace, Views::Links::Badge.new(count: counts.fetch(profile.id)),
                      targets: Views::Links::Badge::SELECTOR)
            sections = Views::Links::Sections.new(viewer: profile, page: page)
            stream_to([ profile, :notifications ], :replace, sections, target: sections.dom_id)
          end
        end
      end
    end

    # The bell rows about a link or its requests lose their buttons once
    # it's settled (the block, if any, settles it).
    def self.request_settled(link)
      notifications = Notification.where(subject: link).or(Notification.where(subject_type: "LinkApproval", subject_id: link.link_approvals.select(:id))).to_a
      yield if block_given?
      notifications.each { |notification| Notifications::Broadcaster.refreshed(notification.reload) }
    end
  end
end
