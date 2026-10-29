# frozen_string_literal: true

module Emails
  # Puts a mail to one person in the outbox (OutgoingEmail). Account mail
  # starts a drain once the transaction it is part of commits; the rest
  # waits a minute, for a drain that starts after whatever queued it has
  # finished, so what falls due together goes together. A row still waiting
  # when its kind stops being worth sending, or by `latest` when that is
  # sooner (a reminder, once its thing is due), fails.
  #
  #   Emails::Enqueue.call(profile, :test_mail)
  #   Emails::Enqueue.call(profile, :email_changed, data: { "to" => old_address })
  #   Emails::Enqueue.call(profile, :reminder, data: { … }, latest: due_at)
  class Enqueue
    GATHER = 1.minute

    def self.call(profile, key, data: {}, now: Time.current, latest: nil)
      kind = Kinds.for(key)
      row = OutgoingEmail.create!(profile: profile, kind: kind.key, data: data, not_before: kind.sends_at_once? ? now : now + GATHER,
                                  expires_at: [ now + kind.waits_at_most, latest ].compact.min)
      ActiveRecord.after_all_transactions_commit { DrainJob.perform_later } if kind.sends_at_once?
      row
    end
  end
end
