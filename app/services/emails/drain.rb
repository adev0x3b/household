# frozen_string_literal: true

module Emails
  # Sends what is due in the outbox, one message at a time, while the
  # installation's budget lasts (Emails::RelayAllowance) and the kinds in
  # their order (Emails::Kinds.all). Run by Emails::DrainJob: every minute,
  # and as soon as account mail is queued.
  #
  # A batch is claimed (sending) under its household's lock, where the
  # kind's room in the household's own budget is checked too, and only
  # then made and sent, so no two drains send one row. Every row ends one
  # way: sent; failed, refused for good, tried too often or kept waiting
  # past its kind's time; or dropped, no longer wanted. A round lasts
  # minutes, so each batch reads the settings again: mail turned off, or a
  # budget lowered, holds from the next.
  #
  # What the relay answers decides what comes next (Emails::Relay): not
  # answering, the batch waits longer each time and the round stops; this
  # copy's settings refused, the batch goes back untouched, the relay
  # pauses and the admin hears of it; one message refused, that batch fails
  # and the round goes on. A refusal that may be of the settings or of the
  # message is told by the mail around it (#maybe_misconfigured), so one
  # bad address never stops everyone's mail. A batch whose message fails to
  # be made, or that meets an error nobody foresaw, fails or waits on its
  # own, reported.
  #
  #   Emails::Drain.call
  class Drain
    # A round takes no new batch after this: the next minute's goes on.
    ROUND = 5.minutes
    # A claim this old was a drain that stopped between claiming and
    # ending its batch: the rows go back, at worst to be sent twice.
    RECLAIM_AFTER = 10.minutes
    ATTEMPTS = 8
    LONGEST_WAIT = 6.hours
    # A household over its budget is asked again after this.
    HELD_FOR_BUDGET = 15.minutes

    def self.call(now: Time.current) = new(now).call

    def initialize(now)
      @started = now
      # Where the mail held this round was to go (#hold).
      @held_to = []
    end

    def call
      reclaim_stalled
      expire_late
      return if RelayPause.current

      while Time.current < @started + ROUND
        Platform::Setting.forget_saved
        break unless Emails.enabled?

        kind, rows, held = claim_next
        break if rows.nil?
        break unless send_batch(kind, rows, held:)
      end
    end

    private

    def reclaim_stalled
      OutgoingEmail.sending.where(claimed_at: ...(@started - RECLAIM_AFTER)).find_each do |row|
        wait(row, :drain_stopped, nil)
      end
    end

    def expire_late
      OutgoingEmail.queued.where(expires_at: ...@started).includes(:profile).group_by { [ _1.kind, _1.profile_id ] }.each_value do |rows|
        expire(rows)
      end
    end

    # The next batch that may go, claimed: [ kind, rows, held ]; nil when
    # nothing may. Mail held for a refusal that may be its own goes after
    # all the rest, so the rest says whether it was: a batch claimed for it
    # is held.
    def claim_next
      allowance = RelayAllowance.new(Time.current)
      claim_first(OutgoingEmail.where(held_for_settings_at: nil), allowance, held: false) ||
        claim_first(OutgoingEmail.where.not(held_for_settings_at: nil), allowance, held: true)
    end

    def claim_first(rows, allowance, held:)
      Kinds.all.each do |kind|
        next unless allowance.allows?(kind)

        while (row = rows.due(Time.current).where(kind: kind.key).order(:not_before, :id).first)
          batch = claim(kind, row)
          return [ kind, batch, held ] if batch.any?
        end
      end
      nil
    end

    # The row's batch, claimed under its household's lock, in the order it
    # was queued; none when the household has no room for it (it waits) or
    # another drain took it.
    def claim(kind, row)
      household = row.profile.household
      household.with_lock do
        now = Time.current
        batch = OutgoingEmail.where(id: kind.batch(row).map(&:id)).queued
        if kind.room_in?(household, now)
          message_id = "#{SecureRandom.uuid}@#{RelaySettings.current.from.split("@").last}"
          batch.update_all(status: :sending, claimed_at: now, message_id: message_id, updated_at: now)
          OutgoingEmail.sending.where(message_id: message_id).includes(:profile).order(:id).to_a
        else
          batch.update_all(not_before: now + HELD_FOR_BUDGET, reason: :over_budget, detail: nil, updated_at: now)
          []
        end
      end
    end

    # False when the round should stop: the relay can't take more now.
    def send_batch(kind, rows, held:)
      outgoing = make(kind, rows) or return true

      answer = relay(kind, outgoing, held:)
      finish(outgoing.rows, :sent, sent_at: Time.current, reason: nil, detail: nil) if answer == :sent
      answer != :stop
    end

    # What came of handing the message to the relay: :sent, :stop, or
    # anything else when the round goes on. The rows are ended or put back
    # here, but for sent, which the caller marks outside these rescues, so
    # a message the relay took is never sent again because of what followed.
    def relay(kind, outgoing, held:)
      Relay.deliver(outgoing.mail)
      :sent
    rescue Relay::Unavailable => e
      Rails.error.report(e, handled: true, severity: :warning, context: context(kind, outgoing.rows))
      outgoing.rows.each { wait(_1, :unavailable, e.detail) }
      :stop
    rescue Relay::Misconfigured => e
      e.maybe_the_message? ? maybe_misconfigured(kind, outgoing, e, held:) : misconfigured(kind, outgoing.rows, e)
    rescue Relay::Refused => e
      refused(kind, outgoing.rows, e)
    rescue *ApplicationJob::TRANSIENT
      raise
    rescue StandardError => e
      Rails.error.report(e, handled: true, severity: :error, context: context(kind, outgoing.rows))
      outgoing.rows.each { wait(_1, :unexpected, detail_of(e)) }
      :stop
    end

    # A refusal in words a relay gives a sender it won't send for and a
    # message it won't take alike. Mail gone out since the batch was first
    # refused, or since this round began, says the settings work: it was
    # the message, which fails. Otherwise the first batch refused so in a
    # round is held, to go after the rest; another address refused so in
    # the same round, or the held batch refused again with nothing gone out
    # in between, says it was the settings. A batch claimed for mail that
    # isn't held is tried as the rest is, though a held row came with it:
    # only mail that waited behind the rest can say that. Until then it is
    # reported as the refusal of a message, so the admin isn't sent to
    # settings that work. Mail gone out under settings changed since counts
    # too: settings that worked and broke again within a pause fail what
    # was held behind them, rather than pause.
    def maybe_misconfigured(kind, outgoing, error, held:)
      held_since = outgoing.rows.filter_map(&:held_for_settings_at).min
      if OutgoingEmail.sent.exists?(sent_at: (held_since || @started)..)
        refused(kind, outgoing.rows, error.as_refusal)
      elsif !held && (@held_to - outgoing.mail.to).empty?
        hold(kind, outgoing, error.as_refusal)
      else
        misconfigured(kind, outgoing.rows, error)
      end
    end

    def hold(kind, outgoing, error)
      Rails.error.report(error, handled: true, severity: :warning, context: context(kind, outgoing.rows))
      put_back(outgoing.rows, :held, error.detail)
      @held_to |= outgoing.mail.to
      :held
    end

    def misconfigured(kind, rows, error)
      Rails.error.report(error, handled: true, severity: :error, context: context(kind, rows))
      put_back(rows, error.maybe_the_message? ? :held : :misconfigured, error.detail)
      RelayPause.start(error)
      :stop
    end

    def refused(kind, rows, error)
      Rails.error.report(error, handled: true, severity: :warning, context: context(kind, rows))
      fail(rows, :refused, error.detail)
      :refused
    end

    # The kind's message, made in its person's language and zone; nil when
    # none is wanted, its rows then dropped. Rows it leaves out are dropped.
    # One that can't be made fails its rows, and the round goes on.
    def make(kind, rows)
      outgoing = rows.first.profile.as_viewer { kind.new(rows).message }
      leftover = outgoing ? rows - outgoing.rows : rows
      drop(leftover) if leftover.any?
      outgoing&.mail&.message_id = rows.first.message_id
      outgoing
    rescue *ApplicationJob::TRANSIENT
      raise
    rescue StandardError => e
      Rails.error.report(e, handled: true, severity: :error, context: context(kind, rows))
      fail(rows, :not_made, detail_of(e))
      nil
    end

    def wait(row, reason, detail)
      attempts = row.attempts + 1
      if attempts >= ATTEMPTS
        fail([ row ], reason, detail)
      else
        row.update_columns(status: :queued, attempts: attempts, claimed_at: nil, message_id: nil, reason: reason, detail: detail,
                           not_before: Time.current + [ (2**attempts).minutes, LONGEST_WAIT ].min, updated_at: Time.current)
      end
    end

    # Back in the queue as it was, for when the settings are fixed. Held,
    # it is marked, and waits a pause's length behind what else is due.
    def put_back(rows, reason, detail)
      now = Time.current
      back = { status: :queued, claimed_at: nil, message_id: nil, reason: reason, detail: detail, updated_at: now }
      held = reason == :held ? { held_for_settings_at: now, not_before: now + RelayPause::LENGTH } : {}
      OutgoingEmail.where(id: rows.map(&:id)).update_all(**back, **held)
    end

    def fail(rows, reason, detail)
      finish(rows, :failed, attempts: rows.first.attempts + 1, reason: reason, detail: detail)
      ended(rows)
    end

    # A row that couldn't go in time didn't go out: it fails, keeping what
    # kept it waiting, if anything did, though no attempt was made.
    def expire(rows)
      rows.each { finish([ _1 ], :failed, reason: _1.reason || :expired) }
      ended(rows)
    end

    def drop(rows)
      finish(rows, :dropped, reason: nil, detail: nil)
      ended(rows)
    end

    # Undoes what making the rows' message did (Emails::Kind#ended). A kind
    # this version has no class for, queued by a newer one before a
    # rollback, is never sent, so it made nothing.
    def ended(rows)
      kind = Kinds.find(rows.first.kind)
      kind.new(rows).ended if kind
    end

    # An ended row keeps no data: an address a notice held goes with it.
    def finish(rows, status, **columns)
      OutgoingEmail.where(id: rows.map(&:id)).update_all(status: status, data: {}, updated_at: Time.current, **columns)
    end

    # What a row keeps of an error the relay didn't answer with
    # (Relay::Error#detail): its class alone, since its message may quote
    # what the mail was to say. The report has the rest.
    def detail_of(error) = error.class.name

    def context(kind, rows) = { kind: kind.key, outgoing_email_ids: rows.map(&:id) }
  end
end
