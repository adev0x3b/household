# frozen_string_literal: true

module Emails
  # What one mail says, in the current language, for both of its parts:
  # the plain text (#text) and the HTML (Views::Emails::Message). Each kind
  # of mail words its own (Emails::TestMailWording):
  #
  #   subject     the subject line, never naming what a mail is about where
  #               a phone's lock screen would show it
  #   heading     the first line: the person, greeted by the name they go by
  #   paragraphs  what it says, in order
  #   items       a list after them (several reminders at once), if any
  #   action      the one thing to press (an Action: label and url), if any
  #   closing     a last, smaller line (why it came, how to stop it), if any
  #   unsubscribe the link that stops mail of its kind (an Action), if any
  class Wording
    Action = Data.define(:label, :url)

    # profile: whom the mail is to.
    def initialize(profile)
      @profile = profile
    end

    def heading = I18n.t("emails.greeting", name: @profile.display_name)

    def paragraphs = []

    def items = []

    def action = nil

    def closing = nil

    def unsubscribe = nil

    def text
      list = items.map { "- #{_1}" }.join("\n").presence
      [ heading, *paragraphs, list, written_out(action), closing, written_out(unsubscribe) ].compact.join("\n\n")
    end

    private

    def written_out(link) = link && "#{link.label}:\n#{link.url}"
  end
end
