# frozen_string_literal: true

module Demo
  # The household's agenda: the chores that come round every week, kept up
  # better as the months go by, the one-off jobs of a home, and the
  # appointments that aren't about health — a dinner with friends, a review
  # at work, Sam's job interview, Robin's internship interview.
  class Chores < Part
    # who, title, notes, priority, recurrence, [ done at the start, done now ], shared with
    ROUTINES = [
      [ :alex, "Take out the recycling", "Paper and plastic go out on Tuesday night", :medium,
        { frequency: "weekly", week_days: %w[tuesday] }, [ 0.75, 0.96 ], :sam ],
      [ :alex, "Water the plants", "Balcony herbs, the monstera and the two ferns", :low,
        { frequency: "daily", interval: 3 }, [ 0.8, 0.92 ], :robin ],
      [ :alex, "Clean the bathroom", nil, :medium, { frequency: "weekly", week_days: %w[saturday] }, [ 0.65, 0.85 ], nil ],
      [ :alex, "Review the month's budget", "Check the finance page against the bank statement", :high,
        { frequency: "monthly" }, [ 0.9, 1.0 ], :sam ],
      [ :sam, "Vacuum the house", "All rooms, the hallway and the stairs", :medium,
        { frequency: "weekly", week_days: %w[monday thursday] }, [ 0.7, 0.9 ], :alex ],
      [ :sam, "Change the bed sheets", nil, :low, { frequency: "weekly", interval: 2, week_days: %w[sunday] }, [ 0.8, 0.9 ], nil ],
      [ :sam, "Wash the car", "Inside too", :low, { frequency: "monthly" }, [ 0.6, 0.7 ], nil ],
      [ :robin, "Do the laundry", "Whites and colors apart", :medium, { frequency: "weekly", week_days: %w[wednesday] }, [ 0.55, 0.85 ], :alex ],
      [ :robin, "Clean the cat's litter box", nil, :medium, { frequency: "daily", interval: 2 }, [ 0.85, 0.95 ], :alex ]
    ].freeze

    # days from today (negative: ago), who, title, priority, what became of it, more (notes, shared, cost, lead)
    JOBS = [
      [ -176, :alex, "Label the fuse box", :low, :done ],
      [ -171, :sam, "Register the new address with the bank", :high, :late ],
      [ -165, :alex, "Book the boiler's yearly service", :high, :done, { notes: "Ask for a morning slot", cost: [ 95, "Termoidraulica Bassi", :housing ] } ],
      [ -160, :robin, "Return the library books", :low, :late ],
      [ -152, :alex, "Fix the leaking kitchen tap", :urgent, :done, { notes: "Plumber's tape is in the toolbox", shared: :sam } ],
      [ -147, :sam, "Renew the parking permit", :high, :done, { cost: [ 60, "Comune di Bologna", :transportation ] } ],
      [ -139, :alex, "Defrost the freezer", :low, :skipped ],
      [ -133, :robin, "Sign up for the autumn exam session", :urgent, :early ],
      [ -128, :sam, "Assemble the new bookshelf", :medium, :done ],
      [ -120, :alex, "Compare electricity providers", :medium, :late ],
      [ -113, :alex, "Book summer holiday flights", :high, :done, { shared: :sam } ],
      [ -108, :sam, "Take the bike in for a service", :medium, :done, { cost: [ 45, "Ciclofficina Reno", :transportation ] } ],
      [ -101, :robin, "Deep clean the oven", :low, :cancelled ],
      [ -96, :alex, "Renew the car insurance", :urgent, :done, { notes: "Policy ends at the end of the month" } ],
      [ -90, :sam, "Hang the hallway mirror", :low, :late ],
      [ -84, :alex, "Find a cat sitter for August", :high, :done, { shared: :robin } ],
      [ -77, :robin, "Clear out the storage room", :medium, :late ],
      [ -70, :alex, "Pack for the holiday", :medium, :done ],
      [ -55, :sam, "Empty the fridge before leaving", :medium, :early ],
      [ -41, :alex, "Sort the holiday photos", :low, :skipped ],
      [ -36, :sam, "Replace the smoke alarm batteries", :high, :done ],
      [ -30, :alex, "Order school books for Robin", :medium, :done, { cost: [ 118.4, "Libreria Mondo", :education ] } ],
      [ -26, :robin, "Renew the student transit card", :high, :done ],
      [ -21, :sam, "Clean the balcony before autumn", :low, :late ],
      [ -17, :alex, "Call the landlord about the intercom", :medium, :done ],
      [ -12, :sam, "Bleed the radiators", :medium, :done ],
      [ -9, :alex, "Book the chimney sweep", :medium, :late ],
      [ -5, :robin, "Take the winter coats to the dry cleaner", :low, :open ],
      [ -3, :sam, "Send the meter readings", :high, :open, { notes: "Gas and water, photos to the provider's app", shared: :alex } ],
      [ -1, :alex, "Return the parcel to the post office", :medium, :open ],
      [ 0, :alex, "Sort the paperwork for the tax return", :high, :in_progress, { shared: :sam } ],
      [ 0, :sam, "Buy a birthday present for Robin", :medium, :open, { shared: :alex, lead: 1 } ],
      [ 2, :alex, "Switch the wardrobes to winter clothes", :low, :open ],
      [ 3, :sam, "Book the car's winter tyre change", :high, :open ],
      [ 5, :robin, "Hand in the internship application", :urgent, :open ],
      [ 6, :alex, "Plan Robin's birthday dinner", :medium, :open, { shared: :sam } ],
      [ 9, :sam, "Renew the home contents insurance", :high, :open ],
      [ 13, :alex, "Service the boiler before winter", :high, :open ],
      [ 20, :alex, "Buy the Christmas train tickets", :medium, :open, { shared: :sam } ]
    ].freeze

    # Appointments of the agenda (an Appointment of a kind other than
    # medical): days from today (or the next such weekday), who, title, kind,
    # with whom, time, place, what became of it, notes, shared with. Entered
    # two weeks ahead, with no dice: the other parts' stories keep their rolls.
    APPOINTMENTS = [
      [ -158, :alex, "Dinner at Giulia and Marco's", :social, "Giulia and Marco", "20:00", "Via del Pratello 18", :done,
        "Bring dessert", :sam ],
      [ -137, :sam, "Yearly review", :work, "Greenleaf Cooperative", "10:00", "Via Libia 54", :done, "Ask about the team lead role", nil ],
      [ -104, :alex, "Brief with Bottega Lume", :work, "Bottega Lume", "11:00", "Via San Felice 22", :done, "The new website: bring sketches", nil ],
      [ -73, :robin, "Modern history exam", :other, "Università di Bologna", "09:00", "Via Zamboni 38", :done, nil, nil ],
      [ -46, :alex, "Aperitivo with the neighbours", :social, "Chiara and Tommaso", "19:00", "Bar Senza Nome", :cancelled,
        "Rained off: next month", :sam ],
      [ -11, :sam, "Bank, mortgage advice", :personal, "BPER Banca", "16:30", "Via Rizzoli 7", :done, nil, :alex ],
      [ :monday, :robin, "Internship interview", :work, "Studio Grafico Tondo", "10:00", "Via del Borgo di San Pietro 90", :open,
        "Bring the portfolio on a USB stick", nil ],
      [ 4, :alex, "Tax return with the accountant", :personal, "Dott.ssa Bellini", "15:00", "Via Marconi 9", :open,
        "The folder with the receipts", :sam ],
      [ 6, :sam, "Job interview at Officina Verde", :work, "Elena Sarti, Officina Verde", "11:30", "Via della Beverara 129", :open,
        "Second round: the case study", :alex ],
      [ 12, :alex, "Dinner with friends", :social, "Giulia and Marco", "20:30", "Osteria dell'Orsa", :open, nil, :sam ]
    ].freeze

    private

    def setup
      ROUTINES.each_with_index { |chore, index| at(start + (index * 2)) { routine(*chore) } }
      JOBS.each { |days, who, title, priority, fate, more| job(who, title, due: today + days, priority: priority, fate: fate, **more.to_h) }
      APPOINTMENTS.each { |appointment| appointment(*appointment) }
    end

    def routine(who, title, notes, priority, recurrence, done, shared)
      first = recurrence[:week_days] ? next_weekday(@now, recurrence[:week_days].first) : @now
      chore = create(send(who), Task.new(title: title, notes: notes, starts_on: first, details_attributes: { priority: priority }),
                     recurrence: recurrence)
      share(chore, with: send(shared)) if shared
      remind(chore, alex, [ 3, "hours" ]) if who == :alex # Alex likes a nudge for their chores
      follow(chore, done: done, skipped: 0.04, late: 0.12, early: 0.05)
    end

    def job(who, title, due:, priority:, fate:, notes: nil, shared: nil, cost: nil, lead: rng.rand(3..9))
      at(entered(due, lead)) do
        task = create(send(who), Task.new(title: title, notes: notes, starts_on: due, details_attributes: { priority: priority }))
        share(task, with: send(shared)) if shared
        remind(task, send(who), [ 1, "days" ]) if %i[high urgent].include?(priority)
        conclude(task, due, fate, cost)
      end
    end

    def conclude(task, due, fate, cost)
      case fate
      when :done then at(due) { done(task, cost) }
      when :early then at(due - 2) { done(task, cost) }
      when :late then at(due + rng.rand(1..3)) { done(task, cost) }
      when :skipped then at(due) { task.first_occurrence.change_status!("skipped") }
      when :cancelled then at(due - 1) { task.first_occurrence.change_status!("cancelled") }
      when :in_progress then at(today) { task.first_occurrence.change_status!("in_progress") }
      end
    end

    def done(task, cost)
      day = task.first_occurrence.complete!
      return unless cost

      price, payee, category = cost
      pay(day, price, on: Date.current, title: task.title, to: payee, category: category)
    end

    def appointment(days, who, title, kind, counterpart, time, place, fate, notes, shared)
      date = days.is_a?(Symbol) ? next_weekday(today + 1, days) : today + days
      at(entered(date, 14)) do
        meeting = create(send(who), Appointment.new(title: title, start_time: time, location: place, notes: notes, starts_on: date,
                                                    details_attributes: { kind: kind, counterpart: counterpart }))
        share(meeting, with: send(shared), read_after: 2.hours) if shared
        remind(meeting, send(who), [ 1, "days" ], [ 2, "hours" ])
        case fate
        when :done then at(date) { meeting.first_occurrence.complete! }
        when :cancelled then at(date - 1) { meeting.first_occurrence.change_status!("cancelled") }
        end
      end
    end
  end
end
