# frozen_string_literal: true

module Emails
  # The message a kind of mail made from its rows (Emails::Kinds): the mail,
  # and the rows of the outbox it carries, which its sending ends.
  Outgoing = Data.define(:mail, :rows)
end
