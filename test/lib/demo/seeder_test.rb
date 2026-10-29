# frozen_string_literal: true

require "test_helper"

class Demo::SeederTest < ActiveSupport::TestCase
  # One run for every assertion: it lives through six months.
  test "the demo household has six months behind it, things to act on today, and is rebuilt from scratch" do
    today = Date.new(2026, 10, 5)
    travel_to today.in_time_zone.change(hour: 9)
    Household.create!(name: "Old demo", slug: Demo::Seeder::SLUG)
    others = Event.count

    out = StringIO.new
    household = Demo::Seeder.call(today: today, out: out)
    alex, sam, robin = household.profiles.order(:id).to_a

    assert_equal [ household ], Household.where(slug: Demo::Seeder::SLUG).to_a
    assert_equal household, Demo::Seeder.household
    assert_nil household.owner, "nobody of the demo can remove the others"
    assert_equal %w[alex.demo sam.demo robin.demo], [ alex, sam, robin ].map(&:username)
    assert alex.valid_password?("demo-household")
    assert [ alex, sam, robin ].all?(&:email_confirmed?), "as the addresses of a household that uses mail"
    assert_predicate EventReminder.for_profile(alex).where(by_email: true), :exists?
    assert_equal others, Event.where.not(profile: household.profiles).count

    # Every kind has series that began months ago, days done, and days ahead.
    events = Event.where(profile: household.profiles)
    Event.types.each do |kind|
      series = events.of_type(kind)
      days = Occurrence.where(event_id: series.select(:id))
      assert_operator series.minimum(:starts_on), :<, today - 150, kind.name
      assert_predicate days.completed, :exists?, kind.name
      ahead = series.visible_in(today, today + 45).any? { |event| event.occurrences_between(today, today + 45).any?(&:open?) }
      assert ahead, kind.name
      assert_match(/#{series.count} #{kind.model_name.human.downcase.pluralize} \(#{days.count} days kept\)/, out.string)
    end

    # The clock was set to each day: nothing was written "now".
    assert_operator Occurrence.of_type(Task).where(event_id: events.select(:id)).minimum(:created_at), :<, today - 150
    assert_operator events.minimum(:created_at), :<, today - 150
    assert_operator SupplyConsumption.where(supply: alex.supplies).minimum(:consumed_at), :<, today - 150

    # Stock follows from what was taken, cooked and bought.
    assert_not alex.ingredients.where("quantity < 0").exists?
    assert_predicate alex.supplies.find_by!(name: "Levothyroxine 75 mcg"), :low_stock?
    assert_equal 1, GroceryList.where(profile: alex).active.count
    assert_operator GroceryList.where(profile: alex).completed.count, :>, 20

    # A dose's plan is on its series (supply uses); a taken dose drew from the cupboard.
    injection = Medication.find_by!(profile: sam, title: "Vitamin B12 1000 mcg")
    assert_equal [ "Needles 23G", "Syringes 2.5 ml", "Vitamin B12 ampoules" ], injection.details.supplies.map(&:name).sort
    assert_predicate injection.occurrences.completed.joins(:supply_consumptions), :exists?
    assert_equal %w[left right], injection.occurrences.completed.order(:date).last(2).map { |dose| dose.details.side }.sort

    # The therapies are healthcare collections: their series and purchases in
    # them, one shared with a housemate who otherwise wouldn't see it.
    therapies = Collection.where(profile: household.profiles)
    assert_equal 5, therapies.in_section(:healthcare).count
    assert_predicate therapies.find_by!(name: "Hay fever"), :completed?
    thyroid = therapies.find_by!(name: "Hypothyroidism")
    assert_equal %w[Appointment LabTestResult Medication], thyroid.events.distinct.pluck(:type).sort
    assert_predicate thyroid.supply_purchases, :exists?
    hay_fever = therapies.find_by!(name: "Hay fever")
    assert_includes Event.accessible_by(alex), hay_fever.events.first
    assert_not Link.between(alex, robin).accepted?

    # Visits are medical appointments with who they're with; their fees hang off them.
    visit = Appointment.find_by!(profile: alex, title: "Endocrinology, first visit")
    assert_equal :healthcare, visit.section
    assert_equal "Dr. Marchetti", visit.counterpart
    fee = visit.first_occurrence.costs.sole
    assert_predicate fee, :completed?
    assert_equal 12_000, fee.details.amount_cents
    assert_equal "healthcare", fee.event.details.category

    # The agenda: tasks and the appointments that aren't medical — a dinner
    # with friends, Sam's job interview — some behind, some ahead.
    agenda = events.in_section(:agenda).of_type(Appointment)
    assert(agenda.any? { |appointment| appointment.details.social? && appointment.first_occurrence.completed? })
    interview = agenda.find { |appointment| appointment.profile == sam && appointment.details.work? && appointment.starts_on > today }
    assert interview, "Sam's job interview"
    assert_equal :agenda, interview.section
    assert_predicate interview.counterpart, :present?
    assert(agenda.any? { |appointment| appointment.details.social? && appointment.starts_on > today })
    assert_equal events.of_type(Task).count + agenda.count, events.in_section(:agenda).count

    # A payment between housemates is one row, read by both: an expense for
    # the payer, an income for the other, who can't change it.
    transfer = Transaction.where(profile: alex).find_by!(title: "Sam's half of the washing machine repair")
    assert_equal sam, transfer.details.counterparty_profile
    assert_includes Event.accessible_by(sam), transfer
    assert_equal "expense", transfer.kind_for(alex)
    assert_equal "income", transfer.kind_for(sam)
    assert_not Transaction.where(profile: sam, title: transfer.title).exists?
    day = transfer.first_occurrence
    assert_predicate day, :completed?
    assert_predicate Pundit.policy!(sam, day), :show?
    assert_not Pundit.policy!(sam, day).update?
    paid_back = Transaction.find_by!(profile: sam, title: "Paid back: concert ticket for Sam")
    assert_equal alex, paid_back.details.counterparty_profile
    assert_equal "income", paid_back.kind_for(alex)

    # A bill that changes month to month keeps each month's amount on its day.
    gas = Transaction.find_by!(profile: alex, title: "Gas")
    amounts = gas.occurrences.completed.map { |bill| bill.details.amount_cents }
    assert_operator amounts.uniq.size, :>, 1

    dashboard = Reports::Home.new(audience: Reports::Audience.new(viewer: alex), today: today)
    assert_equal [ alex, robin, sam ].map(&:id).sort, dashboard.audience.members.map(&:id).sort
    kinds = dashboard.attention.map(&:kind)
    %i[missed_dose supply_running_out batch_expiring appointment_outcome overdue_transaction overdue_task].each do |kind|
      assert_includes kinds, kind
    end
    assert_predicate alex.notifications.unread, :exists?

    # Doses at set times: Sam's metformin twice a day, each dose its own
    # day taken around its time; this evening's still to take.
    metformin = Medication.where(profile: sam).to_a.find(&:timed?)
    assert_equal [ %w[08:00 CM], %w[19:30 CV] ], metformin.slots
    doses = metformin.occurrences
    assert_operator doses.where(time: "19:30").completed.count, :>, 80
    assert_equal 19, doses.where(time: "19:30").completed.order(:date).last.completed_at.hour
    assert_predicate doses.skipped.where.not(skipped_reason: nil), :exists?
    assert_equal([ [ "08:00", "completed" ] ], doses.where(date: today).map { [ _1.time_string, _1.status ] })
    assert_equal([ [ "19:30", true ] ], metformin.occurrences_between(today, today).reject(&:persisted?).map { [ _1.time_string, _1.pending? ] })
    travel_to today.in_time_zone.change(hour: 21)
    tonight = Reports::Home.new(audience: Reports::Audience.new(viewer: sam), today: today)
    assert_includes tonight.attention.map(&:kind), :overdue_dose

    # The shelves: a pile each, one book being read, most finished and rated, Alex's shelf open to Sam.
    assert_operator Book.where(profile: alex).count, :>, 8
    [ alex, sam, robin ].each { |reader| assert_equal 1, reader.books.reading.count, reader.username }
    assert_predicate Book.where(profile: alex).read.where.not(rating: nil), :exists?
    assert_predicate Book.where(profile: household.profiles).dropped, :exists?
    assert_operator Book.where(profile: alex).minimum(:created_at), :<, today - 150
    assert alex.bookshelf.bookshelf_shares.exists?(profile: sam)
    assert_includes Book.accessible_by(sam), Book.where(profile: alex).first
    assert_includes Book.accessible_by(robin), Book.find_by!(title: "Circe")

    # The links: Alex and Sam see each other's calendars, Robin asked today; requests wait for Alex.
    assert_predicate Link.between(alex, sam), :accepted?
    assert_predicate Link.between(alex, robin), :pending?
    assert_includes Event.accessible_by(sam).pluck(:profile_id), alex.id
    assert_not LinkGrant.find_by!(grantor: sam, grantee: alex, event_type: "Medication").read_on?
    assert_predicate LinkApproval.where(owner: alex).approved, :exists?
    assert_predicate LinkApproval.where(owner: alex).declined, :exists?
    assert_operator LinkApproval.live.where(owner: alex).count, :>=, 2
    assert_predicate LinkApproval.live.where(owner: alex, event_type: "Appointment").to_update, :exists?
    assert_predicate alex.notifications.unread.approval_requested, :exists?
    assert_operator Links::Pending.count_for(alex), :>=, 2

    # The conversations: six months of talk, today's still unread by Alex.
    chat = Conversation.household_conversation(household)
    assert_equal Demo::Talk::RENAMED, chat.name
    assert_operator Message.where(sender: household.profiles).count, :>, 40
    assert_operator chat.messages.minimum(:created_at), :<, today - 150
    last_word = Message.where(sender: household.profiles).maximum(:created_at)
    assert_operator last_word, :<, Time.current, "nothing is said after the clock"
    assert_predicate MessageReaction.joins(:message).where(messages: { conversation_id: chat.id }), :exists?
    assert_operator Messages::Unread.count_for(alex), :>, 0
    assert_equal 0, Messages::Unread.count_for(sam)
    assert_predicate alex.notifications.unread.message_received, :exists?
  ensure
    travel_back
  end
end
