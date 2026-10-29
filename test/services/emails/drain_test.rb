# frozen_string_literal: true

require "test_helper"

# Sending what is due: each row ends sent, failed or dropped, and what the
# relay answers decides what comes next.
class Emails::DrainTest < ActiveSupport::TestCase
  setup do
    @admin = profiles(:alice).tap(&:admin!)
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  def queue(profile = @admin, at: Time.current) = Emails::Enqueue.call(profile, :test_mail, now: at)

  def drain(answer: ->(_mail) { }, **relay) = with_relay(relay) { relayed(answer: answer) { Emails::Drain.call } }

  # The relay refusing mail to these people in words it gives a sender it
  # won't send for as well (Emails::Relay::Misconfigured#maybe_the_message?).
  def refuse(*people)
    lambda do |mail|
      next unless people.any? { mail.to == [ _1.email ] }

      raise Emails::Relay::Misconfigured.new(:sender, reply: "554 5.7.1 <#{mail.to.first}>: Recipient address rejected: Access denied")
    end
  end

  test "sends what is due in its person's language, and keeps no more of it than when and under which id" do
    @admin.update!(locale: "it")
    row = queue

    mails = drain

    assert_equal 1, mails.size
    assert_equal [ "alice@example.com" ], mails.first.to
    assert_equal "Un'email di prova da Household", mails.first.subject
    row.reload
    assert_predicate row, :sent?
    assert_equal row.message_id, mails.first.message_id
    assert_match(/@household\.example\z/, row.message_id)
    assert_in_delta Time.current, row.sent_at, 1.second
    assert_equal({}, row.data)
  end

  test "nothing goes while mail is off, its relay isn't set, or it is paused, and nothing waiting is lost" do
    row = queue
    refuse = ->(_mail) { flunk "handed to the relay" }

    relayed(answer: refuse) { Emails::Drain.call }
    drain(answer: refuse, "OUTGOING_MAIL" => "off")
    Emails::RelayPause.start(Emails::Relay::Misconfigured.new(:login))
    drain(answer: refuse)

    assert_predicate row.reload, :queued?
  end

  test "a relay that isn't answering keeps the mail waiting, longer each time, then gives up; the rest isn't tried meanwhile" do
    row, behind = queue, queue
    down = lambda do |_mail|
      raise Errno::ECONNREFUSED
    rescue Errno::ECONNREFUSED
      raise Emails::Relay::Unavailable, "The mail relay isn't answering (ECONNREFUSED)"
    end

    report = assert_error_reported(Emails::Relay::Unavailable) { assert_equal 1, drain(answer: down).size }

    assert_equal :warning, report.severity
    behind.reload
    assert_equal [ "queued", 0 ], [ behind.status, behind.attempts ]
    assert_in_delta Time.current, behind.not_before, 1.second
    row.reload
    assert_predicate row, :queued?
    assert_equal 1, row.attempts
    assert_in_delta 2.minutes.from_now, row.not_before, 1.second
    assert_equal [ "unavailable", "Errno::ECONNREFUSED" ], [ row.reason, row.detail ]
    assert_nil row.message_id

    row.update!(attempts: Emails::Drain::ATTEMPTS - 1, not_before: 1.minute.ago)
    drain(answer: down)
    assert_equal [ "failed", "unavailable" ], [ row.reload.status, row.reason ]
  end

  test "the relay refusing this copy's settings puts the mail back as it was, pauses, and reports what to fix" do
    row = queue
    misconfigured = ->(_mail) { raise Emails::Relay::Misconfigured.new(:login, reply: "535 5.7.8 Authentication credentials invalid") }

    report = assert_error_reported(Emails::Relay::Misconfigured) { drain(answer: misconfigured) }

    assert_equal :error, report.severity
    row.reload
    assert_predicate row, :queued?
    assert_equal [ 0, nil, nil, nil ], [ row.attempts, row.claimed_at, row.message_id, row.held_for_settings_at ]
    assert_in_delta Time.current, row.not_before, 1.second
    assert_equal [ "misconfigured", "535 5.7.8 Authentication credentials invalid" ], [ row.reason, row.detail ]
    assert_equal :login, Emails::RelayPause.current.problem
  end

  test "a refusal that may be of the message holds that mail behind the rest, and fails it once other mail went out" do
    bob = profiles(:bob).tap(&:admin!)
    held, other = queue(bob), queue

    report = assert_error_reported(Emails::Relay::Refused) { assert_equal 2, drain(answer: refuse(bob)).size }

    assert_equal [ :warning, "The mail relay refused a message (554 5.7.1)" ], [ report.severity, report.error.message ],
                 "a message refused, not settings to fix, until the mail around it says so"
    held.reload
    assert_equal [ "queued", "held", "554 5.7.1 <[address]>: Recipient address rejected: Access denied" ], [ held.status, held.reason, held.detail ]
    assert_in_delta Time.current, held.held_for_settings_at, 1.second
    assert_in_delta Emails::RelayPause::LENGTH.from_now, held.not_before, 1.second
    assert_predicate other.reload, :sent?
    assert_nil Emails::RelayPause.current, "the rest went on"

    held.update!(expires_at: 1.day.from_now)
    travel Emails::RelayPause::LENGTH + 1.second
    assert_error_reported(Emails::Relay::Refused) { drain(answer: refuse(bob)) }

    assert_equal [ "failed", "refused" ], [ held.reload.status, held.reason ]
    assert_nil Emails::RelayPause.current
  end

  test "a refusal that may be of the message fails it at once when other mail went out this round" do
    bob = profiles(:bob).tap(&:admin!)
    sent, refused = queue, queue(bob)

    report = assert_error_reported(Emails::Relay::Refused) { drain(answer: refuse(bob)) }

    assert_equal "554 5.7.1 <[address]>: Recipient address rejected: Access denied", report.error.detail

    assert_predicate sent.reload, :sent?
    assert_equal [ "failed", "refused", nil ], [ refused.reload.status, refused.reason, refused.held_for_settings_at ]
  end

  test "a second address refused so in one round says it was the settings: the relay pauses, and the rest waits" do
    bob, carol = profiles(:bob).tap(&:admin!), profiles(:carol).tap(&:admin!)
    first, second, behind = queue(bob), queue(carol), queue

    reports = capture_error_reports { assert_equal 2, drain(answer: refuse(bob, carol)).size }

    assert_equal([ [ Emails::Relay::Refused, :warning ], [ Emails::Relay::Misconfigured, :error ] ], reports.map { [ _1.error.class, _1.severity ] })
    assert_equal([ %w[queued held] ] * 2, [ first, second ].map { [ _1.reload.status, _1.reason ] })
    assert second.held_for_settings_at
    assert_equal :sender, Emails::RelayPause.current.problem
    assert_predicate behind.reload, :queued?
    assert_nil behind.reason
  end

  test "a held mail refused again with nothing gone out in between pauses the relay" do
    bob = profiles(:bob).tap(&:admin!)
    held = queue(bob).tap { _1.update!(expires_at: 1.day.from_now) }
    assert_error_reported(Emails::Relay::Refused) { drain(answer: refuse(bob)) }
    assert_nil Emails::RelayPause.current

    travel Emails::RelayPause::LENGTH + 1.second
    report = assert_error_reported(Emails::Relay::Misconfigured) { drain(answer: refuse(bob)) }

    assert_equal :error, report.severity
    assert_equal :sender, Emails::RelayPause.current.problem
    held.reload
    assert_equal [ "queued", "held" ], [ held.status, held.reason ]
    assert_in_delta Emails::RelayPause::LENGTH.from_now, held.not_before, 1.second
  end

  test "a held mail goes after all other mail due, whatever its kind" do
    bob = profiles(:bob).tap { _1.update!(email_confirmed_at: 1.day.ago) }
    Emails::Enqueue.call(bob, :password_changed, data: { "to" => bob.email }).update!(held_for_settings_at: 20.minutes.ago, not_before: 5.minutes.ago)
    queue

    assert_equal [ [ @admin.email ], [ bob.email ] ], drain.map(&:to)
  end

  test "a new mail to someone whose mail is held goes with it afresh, and refused, both are held behind the rest, which goes" do
    bob = profiles(:bob).tap { _1.update!(email_confirmed_at: 1.day.ago) }
    held = Emails::Enqueue.call(bob, :password_changed, data: { "to" => bob.email })
    held.update!(status: :queued, reason: :held, held_for_settings_at: 2.minutes.ago, not_before: 13.minutes.from_now)
    fresh = Emails::Enqueue.call(bob, :password_changed, data: { "to" => bob.email })
    other = queue

    reports = capture_error_reports { assert_equal 2, drain(answer: refuse(bob)).size }

    assert_equal([ Emails::Relay::Refused ], reports.map { _1.error.class })
    assert_nil Emails::RelayPause.current, "one address refused stops nobody's mail"
    assert_predicate other.reload, :sent?
    assert_equal([ %w[queued held] ] * 2, [ held, fresh ].map { [ _1.reload.status, _1.reason ] })
  end

  test "a held mail a new one brings along keeps what went out since it was held: refused again, it was the message's, and nobody's mail stops" do
    bob, carol = [ profiles(:bob), profiles(:carol) ].each { _1.update!(email_confirmed_at: 1.day.ago) }
    held = Emails::Enqueue.call(bob, :password_changed, data: { "to" => bob.email })
    held.update!(reason: :held, held_for_settings_at: 10.minutes.ago, not_before: 5.minutes.from_now)
    queue.update!(status: :sent, sent_at: 9.minutes.ago)
    Emails::Enqueue.call(carol, :password_changed, data: { "to" => carol.email })
    fresh = Emails::Enqueue.call(bob, :password_changed, data: { "to" => bob.email })

    reports = capture_error_reports { drain(answer: refuse(bob, carol)) }

    assert_equal([ Emails::Relay::Refused ] * 2, reports.map { _1.error.class })
    assert_nil Emails::RelayPause.current, "mail went out since the held one was first refused: the settings work"
    assert_equal([ %w[failed refused] ] * 2, [ held, fresh ].map { [ _1.reload.status, _1.reason ] })
  end

  test "a relay that refuses every message fails no more of them in an hour than the budget" do
    rows = Array.new(3) { queue }
    refuse_all = ->(_mail) { raise Emails::Relay::Refused.new("The mail relay refused a message (550)", reply: "550 Relaying denied") }

    assert_error_reported(Emails::Relay::Refused) { drain("MAILS_PER_HOUR" => "3", answer: refuse_all) }

    assert_equal(%w[failed failed queued], rows.map { _1.reload.status })
  end

  test "an error nobody foresaw keeps the mail waiting, reported, and stops the round" do
    first, second = queue, queue
    broken = ->(_mail) { raise ArgumentError, "SMTP-AUTH requested but missing user name" }

    report = assert_error_reported(ArgumentError) { assert_equal 1, drain(answer: broken).size }

    assert_equal :error, report.severity
    first.reload
    assert_predicate first, :queued?
    assert_equal [ 1, "unexpected", "ArgumentError" ], [ first.attempts, first.reason, first.detail ]
    assert_equal [ "queued", 0 ], [ second.reload.status, second.attempts ]
  end

  test "a kind this version has no class for, queued by a newer one before a rollback, is never sent and ends in its time" do
    late = queue(at: 20.minutes.ago)
    waiting = queue
    stalled = queue.tap { _1.update!(status: :sending, claimed_at: 11.minutes.ago, attempts: Emails::Drain::ATTEMPTS - 1) }

    mails = swapping(Emails::Kinds, :all, -> { [ Emails::Kinds::PasswordChanged ] }) { drain }

    assert_empty mails
    assert_predicate late.reload, :failed?
    assert_predicate waiting.reload, :queued?
    assert_predicate stalled.reload, :failed?
  end

  test "a message the relay refuses fails, with its reply's addresses masked, and the next one still goes" do
    refused, sent = queue, queue
    handed = 0
    refuse_the_first = lambda do |_mail|
      handed += 1
      raise Emails::Relay::Refused.new("The mail relay refused a message (550 5.1.1)", reply: "550 5.1.1 <alice@example.com>: Recipient address rejected") if handed == 1
    end

    assert_error_reported(Emails::Relay::Refused) { drain(answer: refuse_the_first) }

    assert_predicate refused.reload, :failed?
    assert_equal [ "refused", "550 5.1.1 <[address]>: Recipient address rejected" ], [ refused.reason, refused.detail ]
    assert_equal 1, refused.attempts
    assert_predicate sent.reload, :sent?
  end

  test "a message that can't be made fails on its own, keeping only the error's class, and the next one still goes" do
    broken, sent = queue, queue
    with = AdminMailer.method(:with)
    calls = 0
    failing_once = lambda do |**params|
      calls += 1
      raise ArgumentError, "words of #{params[:profile].first_name}'s" if calls == 1

      with.call(**params)
    end

    mails = nil
    swapping(AdminMailer, :with, failing_once) { assert_error_reported(ArgumentError) { mails = drain } }

    assert_equal 1, mails.size
    assert_predicate broken.reload, :failed?
    assert_equal [ "not_made", "ArgumentError" ], [ broken.reason, broken.detail ]
    assert_predicate sent.reload, :sent?
  end

  test "a mail its kind no longer wants is dropped, never sent" do
    row = queue(profiles(:bob)).tap { _1.update!(reason: :over_budget) }

    assert_empty drain
    assert_predicate row.reload, :dropped?
    assert_nil row.reason
  end

  test "the installation's budget holds back what it can't send yet, and what it keeps for account mail" do
    rows = Array.new(3) { queue }

    mails = drain("MAILS_PER_HOUR" => "3")

    assert_equal 2, mails.size
    assert_equal(%w[sent sent queued], rows.map { _1.reload.status })
  end

  test "a mail a stopped drain had claimed waits again, and one kept past its time fails, saying what kept it, if anything did" do
    stalled = queue.tap { _1.update!(status: :sending, claimed_at: 11.minutes.ago, message_id: "stalled@household.example") }
    kept = queue(at: 20.minutes.ago).tap { _1.update!(reason: :unavailable, detail: "Errno::ECONNREFUSED") }
    late = queue(at: 20.minutes.ago)
    claimed_now = queue.tap { _1.update!(status: :sending, claimed_at: 1.minute.ago, message_id: "now@household.example") }

    Emails::Drain.call

    stalled.reload
    assert_equal [ "queued", 1, nil, "drain_stopped" ], [ stalled.status, stalled.attempts, stalled.message_id, stalled.reason ]
    assert_equal [ "failed", "unavailable", "Errno::ECONNREFUSED" ], [ kept.reload.status, kept.reason, kept.detail ]
    assert_equal [ "failed", "expired" ], [ late.reload.status, late.reason ]
    assert_predicate claimed_now.reload, :sending?
  end

  test "each batch goes by the settings saved by then: mail turned off meanwhile stops the round" do
    first, second = queue, queue
    Platform::Setting.create!(outgoing_mail: true)
    turned_off_meanwhile = ->(_mail) { Platform::Setting.update_all(outgoing_mail: false) }

    assert_equal 1, drain(answer: turned_off_meanwhile).size

    assert_predicate first.reload, :sent?
    assert_predicate second.reload, :queued?
  end

  test "a household's account mail takes no more than its share of the budget; the rest waits, and another household's goes" do
    people = [ @admin, profiles(:bob), profiles(:carol), profiles(:outsider) ]
    people.each { _1.update!(email_confirmed_at: 1.day.ago) }
    rows = people.map { Emails::Enqueue.call(_1, :password_changed, data: { "to" => _1.email }) }

    mails = drain("MAILS_PER_HOUR" => "4")

    assert_equal [ [ @admin.email ], [ profiles(:bob).email ], [ profiles(:outsider).email ] ], mails.map(&:to)
    waiting = rows.third.reload
    assert_equal [ "queued", "over_budget" ], [ waiting.status, waiting.reason ]
    assert_in_delta Emails::Drain::HELD_FOR_BUDGET.from_now, waiting.not_before, 1.second
  end

  test "notices of a password changed again before the first went out go as one, telling of the first" do
    @admin.update!(email_confirmed_at: 1.day.ago)
    rows = [ Time.utc(2026, 10, 29, 9, 30), Time.utc(2026, 10, 29, 9, 50) ].map do |at|
      travel_to(at) { Emails::Enqueue.call(@admin, :password_changed, data: { "to" => @admin.email }) }
    end

    mails = travel_to(Time.utc(2026, 10, 29, 9, 55)) { drain }

    assert_equal 1, mails.size
    assert_includes mails.first.text_part.body.to_s, "Changed on October 29, 2026 09:30."
    assert_equal [ "sent" ], rows.map { _1.reload.status }.uniq
    assert_equal 1, rows.map(&:message_id).uniq.size
  end
end
