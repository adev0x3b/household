# frozen_string_literal: true

module Demo
  # The household's healthcare, as three stories the pages can tell:
  #
  #   Alex   an underactive thyroid found six months ago: a daily tablet,
  #          the dose raised after the third blood test, TSH coming down
  #          into range test after test; vitamin D drops once a week
  #   Sam    a vitamin B12 deficiency: a weekly injection (ampoule, syringe,
  #          needles, each drawn from stock), B12 climbing back; six weeks
  #          of physiotherapy in the summer; metformin twice a day, with
  #          breakfast and dinner, since the glucose came back high
  #   Robin  hay fever in the spring: six weeks of eye drops, a therapy
  #          that is over; a week of antibiotics every eight hours
  #
  # Stock is bought when it runs low, so batches, costs and what is left
  # follow from the doses actually taken.
  class Health < Part
    PHARMACY = "Farmacia Sant'Orsola"
    LAB = "Laboratorio Analisi San Vitale"
    SHELF_LIFE = 540

    # analyte, unit, bounds (per sex where they differ)
    RANGES = [
      [ "TSH", "mIU/L", { low: 0.4, high: 4.0, critical_high: 10 } ],
      [ "Free T4", "ng/dL", { low: 0.8, high: 1.8 } ],
      [ "Glucose", "mg/dL", { low: 70, high: 100, critical_low: 54, critical_high: 250 } ],
      [ "Cholesterol", "mg/dL", { high: 200 } ],
      [ "Vitamin D", "ng/mL", { low: 30, high: 100, critical_low: 10 } ],
      [ "Vitamin B12", "pg/mL", { low: 200, high: 900, critical_low: 150 } ],
      [ "Folate", "ng/mL", { low: 3, high: 17 } ],
      [ "Ferritin", "ng/mL", { low: 15, high: 150 } ],
      [ "Hemoglobin", "g/dL", { low: 12.0, high: 15.5, sex: :female } ],
      [ "Hemoglobin", "g/dL", { low: 13.5, high: 17.5, sex: :male } ]
    ].freeze

    # days from today, who, title, values, fee, therapy (a healthcare collection), notes
    LABS = [
      [ -178, :alex, "Thyroid panel and routine bloods", { "TSH" => 6.8, "Free T4" => 0.9, "Glucose" => 88, "Cholesterol" => 214,
                                                           "Vitamin D" => 18, "Hemoglobin" => 13.1, "Ferritin" => 22 }, 48, :thyroid,
        "Always tired since the winter. Fasting, 8:00" ],
      [ -174, :sam, "Blood count and B12", { "Vitamin B12" => 172, "Folate" => 5.1, "Hemoglobin" => 12.9, "Glucose" => 93, "Cholesterol" => 187 },
        42, :b12, "Tingling in the hands for a few weeks" ],
      [ -128, :alex, "Thyroid panel", { "TSH" => 5.2, "Free T4" => 1.0 }, 24, :thyroid, "Six weeks on 50 mcg" ],
      [ -110, :sam, "B12 follow-up", { "Vitamin B12" => 318, "Hemoglobin" => 13.8 }, 26, :b12, nil ],
      [ -94, :alex, "Thyroid panel and vitamin D", { "TSH" => 4.6, "Free T4" => 1.0, "Vitamin D" => 26 }, 32, :thyroid,
        "Still above range: bring to the endocrinologist" ],
      [ -45, :alex, "Thyroid panel", { "TSH" => 3.1, "Free T4" => 1.2, "Cholesterol" => 198 }, 28, :thyroid, "Six weeks on 75 mcg" ],
      [ -25, :sam, "B12 follow-up", { "Vitamin B12" => 468, "Folate" => 7.2, "Hemoglobin" => 14.6 }, 30, :b12, nil ],
      [ -6, :alex, "Thyroid panel and vitamin D", { "TSH" => 2.4, "Free T4" => 1.3, "Vitamin D" => 34 }, 32, :thyroid, nil ],
      [ 38, :alex, "Thyroid panel", {}, nil, :thyroid, "Fasting. Take the tablet after the draw" ]
    ].freeze

    # days from today, who, title, provider (the counterpart of a medical appointment), time, place, fee,
    # what became of it, therapy, notes
    VISITS = [
      [ -172, :alex, "Endocrinology, first visit", "Dr. Marchetti", "09:30", "Poliambulatorio Saragozza", 120, :done, :thyroid,
        "Start levothyroxine 50 mcg, bloods again in six weeks" ],
      [ -170, :sam, "Hematology consultation", "Dr. Rinaldi", "15:00", "Ospedale Sant'Orsola", 130, :done, :b12,
        "Weekly B12 injections for six months" ],
      [ -160, :robin, "Allergy visit", "Dr. Fabbri", "11:15", "Poliambulatorio Saragozza", 85, :done, :hay_fever, "Eye drops for six weeks" ],
      [ -150, :sam, "Dental cleaning", "Dr. Ferraro", "08:45", "Studio Dentistico Ferraro", 70, :done, nil, nil ],
      [ -131, :alex, "Gynecology check-up", "Dr. Galli", "17:30", "Consultorio Mazzini", 110, :done, nil, nil ],
      [ -121, :robin, "Dentist check-up", "Dr. Ferraro", "16:00", "Studio Dentistico Ferraro", nil, :cancelled, nil, "Exam that day: rebook" ],
      [ -90, :alex, "Endocrinology follow-up", "Dr. Marchetti", "10:00", "Poliambulatorio Saragozza", 90, :done, :thyroid,
        "TSH still high: raise to 75 mcg" ],
      [ -74, :robin, "Eye test", "Ottica Benassi", "18:00", "Via Mazzini 41", 25, :done, nil, nil ],
      [ -60, :sam, "Hematology follow-up", "Dr. Rinaldi", "15:30", "Ospedale Sant'Orsola", 90, :done, :b12, "Responding well, keep going" ],
      [ -20, :alex, "Dermatology, mole check", "Dr. Neri", "12:00", "Poliambulatorio Saragozza", 95, :done, nil, "All fine, again in a year" ],
      [ -8, :sam, "Flu shot", "Dr. Conti", "08:15", "Casa della Salute Navile", nil, :done, nil, nil ],
      [ -12, :alex, "Eye test", "Ottica Benassi", "18:30", "Via Mazzini 41", nil, :open, nil, nil ],
      [ 9, :alex, "Endocrinology follow-up", "Dr. Marchetti", "09:00", "Poliambulatorio Saragozza", 90, :open, :thyroid, "Bring the last two blood tests" ],
      [ 16, :robin, "Dentist check-up", "Dr. Ferraro", "16:30", "Studio Dentistico Ferraro", 50, :open, nil, nil ],
      [ 23, :sam, "Dental cleaning", "Dr. Ferraro", "08:45", "Studio Dentistico Ferraro", 70, :open, nil, nil ],
      [ 31, :sam, "Hematology follow-up", "Dr. Rinaldi", "15:00", "Ospedale Sant'Orsola", 90, :open, :b12, nil ]
    ].freeze

    # Alex's dose goes from 50 to 75 mcg the day after the second endocrinology visit.
    DOSE_RAISED = 88
    # The second bottle of drops was opened this many days ago: 90 days once open, so it runs out the day after tomorrow.
    DROPS_REOPENED = 88

    private

    def setup
      therapies
      supplies
      [ alex, sam, robin ].each { |person| RANGES.each { |name, unit, bounds| range(person, name, unit, **bounds) } }
      LABS.each { |lab| labs(*lab) }
      VISITS.each { |visit| visit(*visit) }
      at(ago(171)) { thyroid_tablets }
      at(ago(176)) { vitamin_d_drops }
      at(ago(168)) { b12_injections }
      at(ago(158)) { hay_fever_drops }
      at(ago(120)) { metformin_tablets }
      at(ago(40)) { antibiotic_course }
      at(ago(5)) { tonsillitis_course }
      at(ago(100)) { physiotherapy }
      [ 151, 122, 97, 71, 44, 29, 13 ].each { |days| at(ago(days)) { painkiller } }
    end

    def daily(day)
      @restocks.each do |restock|
        next unless restock[:during].cover?(day) && restock[:supply].total_remaining <= restock[:below]

        buy(restock[:supply], restock[:pack], restock[:price], therapy: restock[:therapy])
      end
    end

    # A therapy is a collection of the healthcare section: its visits, doses,
    # lab results and purchases, shared as one.
    def therapies
      @therapies = {
        thyroid: therapy(alex, "Hypothyroidism", "Levothyroxine every morning, 30 minutes before breakfast. Dr. Marchetti."),
        vitamin_d: therapy(alex, "Vitamin D", "25,000 IU once a week until back above 30 ng/mL."),
        b12: therapy(sam, "Vitamin B12 deficiency", "1000 mcg into the arm once a week, alternating sides. Dr. Rinaldi."),
        hay_fever: therapy(robin, "Hay fever", "Antihistamine eye drops through the pollen season."),
        glucose: therapy(sam, "Blood sugar", "Metformin 500 mg with breakfast and with dinner. Dr. Rinaldi.")
      }
      at(ago(169)) { share(@therapies[:thyroid], with: sam) }
      at(ago(167)) { share(@therapies[:b12], with: alex) }
      at(ago(158)) { share(@therapies[:hay_fever], with: alex) }
    end

    def therapy(owner, name, notes) = Collection.create!(profile: owner, name: name, notes: notes, section: "healthcare")

    def supplies
      @supplies = {
        levo50: supply(alex, "Levothyroxine 50 mcg", :medication, "tablets", low: 7),
        levo75: supply(alex, "Levothyroxine 75 mcg", :medication, "tablets", low: 7),
        drops: supply(alex, "Vitamin D3 drops", :medication, "ml", low: 2, pao_days: 90),
        ibuprofen: supply(alex, "Ibuprofen 400 mg", :medication, "tablets", low: 4),
        ampoules: supply(sam, "Vitamin B12 ampoules", :medication, "ampoules", low: 2),
        syringes: supply(sam, "Syringes 2.5 ml", :consumable, "pieces", low: 3),
        needles: supply(sam, "Needles 23G", :consumable, "pieces", low: 6),
        eye_drops: supply(robin, "Antihistamine eye drops", :medication, "ml", low: nil, pao_days: 28),
        metformin: supply(sam, "Metformin 500 mg", :medication, "tablets", low: 10),
        amoxicillin: supply(robin, "Amoxicillin 1 g", :medication, "tablets", low: nil),
        co_amoxiclav: supply(alex, "Amoxicillin and clavulanic acid 875/125 mg", :medication, "tablets", low: nil)
      }
      @restocks = [
        { supply: @supplies[:levo50], pack: 50, price: 3.8, below: 6, therapy: @therapies[:thyroid], during: ago(171)..ago(DOSE_RAISED + 12) },
        { supply: @supplies[:ampoules], pack: 10, price: 12.4, below: 1, therapy: @therapies[:b12], during: ago(169)..today },
        { supply: @supplies[:syringes], pack: 10, price: 3.9, below: 1, therapy: @therapies[:b12], during: ago(169)..today },
        { supply: @supplies[:needles], pack: 50, price: 5.2, below: 4, therapy: @therapies[:b12], during: ago(169)..today },
        { supply: @supplies[:metformin], pack: 60, price: 4.2, below: 9, therapy: @therapies[:glucose], during: ago(120)..today }
      ]
      # The new strength comes in boxes of 30: the third one is nearly finished.
      [ DOSE_RAISED + 1, 61, 33 ].each { |days| at(ago(days)) { buy(@supplies[:levo75], 30, 4.6, therapy: @therapies[:thyroid]) } }
      # In the medicine cabinet since before the app, and close to its date.
      at(ago(180)) { buy(@supplies[:ibuprofen], 20, 6.9, expires_on: today + 12) }
    end

    def supply(owner, name, category, unit_label, low:, pao_days: nil)
      Supply.create!(profile: owner, name: name, category: category, unit_label: unit_label, low_stock_threshold: low, pao_days: pao_days)
    end

    def buy(supply, quantity, price, therapy: nil, expires_on: Date.current + SHELF_LIFE, opened_on: nil)
      purchase = SupplyPurchase.create!(supply: supply, profile: supply.profile, collection: therapy, quantity_purchased: quantity,
                                        purchased_on: Date.current, expires_on: expires_on, opened_on: opened_on)
      pay(purchase, price, on: purchase.purchased_on, to: PHARMACY)
      purchase
    end

    # What's left of an opened bottle goes in the bin.
    def discard(supply)
      supply.supply_purchases.where("quantity_remaining > 0").update_all(quantity_remaining: 0)
    end

    def range(person, name, unit, sex: :any, **bounds)
      analyte = Analyte.find_or_create_by_name(name, profile_id: person.id)
      unit = Unit.find_or_create_by_name(unit, household_id: person.household_id)
      ReferenceRange.find_or_create_by!(analyte: analyte, unit: unit, sex: sex) { |range| range.assign_attributes(bounds) }
    end

    def unit_of(name) = RANGES.find { |analyte, _unit, _bounds| analyte == name }&.second

    def labs(days, who, title, values, fee, therapy, notes)
      date = today + days
      at(entered(date, 6)) do
        result = create(send(who), LabTestResult.new(title: title, notes: notes, starts_on: date), collection: @therapies[therapy])
        next if values.empty?

        # The values come back on the day of the draw, on that day.
        at(date) do
          day = result.first_occurrence.materialize!
          values.each { |name, value| day.lab_test_result_entries.create!(analyte_name: name, unit_name: unit_of(name), value: value.to_s) }
          day.complete!
          pay(day, fee, on: date, title: "Lab tests: #{title.downcase}", to: LAB)
        end
      end
    end

    def visit(days, who, title, provider, time, place, fee, fate, therapy, notes)
      date = today + days
      at(entered(date, rng.rand(10..25))) do
        appointment = create(send(who), Appointment.new(title: title, start_time: time, location: place, notes: notes, starts_on: date,
                                                        details_attributes: { kind: :medical, counterpart: provider }),
                             collection: @therapies[therapy])
        pay(appointment.first_occurrence, fee, on: date, to: provider, category: appointment.fee_category, status: :pending) if fee
        remind(appointment, send(who), [ 1, "days" ], [ 2, "hours" ])
        case fate
        when :done then at(date) { attend(appointment.first_occurrence) }
        when :cancelled then at(date - 2) { appointment.first_occurrence.change_status!("cancelled") }
        end
      end
    end

    # The visit happened, and its fee was paid there.
    def attend(visit)
      visit.complete!
      visit.costs.each(&:complete!)
    end

    # 50 mcg every morning, then 75 mcg once the third blood test showed it wasn't enough.
    def thyroid_tablets
      first = dose(alex, "Levothyroxine 50 mcg", :pill, 50, "mcg", { levo50: 1 }, therapy: :thyroid, pill_count: 1,
                                                                                  recurrence: { frequency: "daily", ends: ago(DOSE_RAISED + 1) })
      follow(first, done: [ 0.9, 0.95 ], skipped: 0.01, late: 0)

      at(ago(DOSE_RAISED)) do
        raised = dose(alex, "Levothyroxine 75 mcg", :pill, 75, "mcg", { levo75: 1 }, therapy: :thyroid, pill_count: 1,
                                                                                     recurrence: { frequency: "daily" })
        follow(raised, done: 0.96, skipped: 0.01, late: 0, force: { ago(2) => :missed, ago(1) => :done })
      end
    end

    # Once a week from a bottle that keeps 90 days once opened: the first one was
    # thrown away with a third still in it, the second is about to go the same way.
    def vitamin_d_drops
      buy(@supplies[:drops], 10, 14.5, therapy: @therapies[:vitamin_d], opened_on: Date.current)
      drops = dose(alex, "Vitamin D3 25,000 IU", :drops, 0.5, "ml", { drops: 0.5 }, therapy: :vitamin_d, recurrence: { frequency: "weekly" })
      follow(drops, done: [ 0.8, 0.95 ], skipped: 0.03, late: 0.2)

      at(ago(DROPS_REOPENED)) do
        discard(@supplies[:drops])
        buy(@supplies[:drops], 10, 14.5, therapy: @therapies[:vitamin_d], opened_on: Date.current)
      end
    end

    def b12_injections
      injection = dose(sam, "Vitamin B12 1000 mcg", :injection, 1, "ml", { ampoules: 1, syringes: 1, needles: 2 }, therapy: :b12,
                                                                                                                   area: :arm, side: :left, recurrence: { frequency: "weekly" })
      follow(injection, done: [ 0.85, 0.97 ], skipped: 0.02, late: 0.2)
    end

    # Six weeks of drops, two bottles (each keeps four weeks once opened), and it's over.
    def hay_fever_drops
      buy(@supplies[:eye_drops], 10, 11.8, therapy: @therapies[:hay_fever], opened_on: Date.current)
      course = dose(robin, "Antihistamine eye drops", :drops, 1, "drop per eye", { eye_drops: 0.1 }, therapy: :hay_fever,
                                                                                                     recurrence: { frequency: "daily", ends: Date.current + 41 })
      follow(course, done: [ 0.75, 0.85 ], skipped: 0.05, late: 0)

      at(Date.current + 27) do
        discard(@supplies[:eye_drops])
        buy(@supplies[:eye_drops], 10, 11.8, therapy: @therapies[:hay_fever], opened_on: Date.current)
      end
      at(Date.current + 43) do
        discard(@supplies[:eye_drops])
        @therapies[:hay_fever].update!(status: :completed)
      end
    end

    # Twice a day with meals, each dose its own: this morning's taken, this
    # evening's still to take (so the home page shows it overdue tonight).
    def metformin_tablets
      tablets = dose(sam, "Metformin 500 mg", :pill, 500, "mg", { metformin: 1 }, therapy: :glucose, pill_count: 1,
                                                                                  recurrence: { frequency: "daily", slots: %w[CM CV] })
      follow(tablets, done: [ 0.85, 0.95 ], skipped: 0.03, late: 0, apart: true,
                      force: { [ today, "08:00" ] => :done, [ today, "19:30" ] => :missed })
    end

    # A week of antibiotics every eight hours, bought the day they were prescribed.
    def antibiotic_course
      buy(@supplies[:amoxicillin], 21, 9.6)
      course = dose(robin, "Amoxicillin 1 g", :pill, 1, "g", { amoxicillin: 1 }, pill_count: 1,
                                                                                 recurrence: { frequency: "daily", ends: ago(34), slots: %w[06:00 14:00 22:00] })
      follow(course, done: 0.95, skipped: 0.05, late: 0, apart: true)
    end

    # Twice a day for two weeks, entered as ending after 15 days: the doctor
    # counted the day it was prescribed. Still under way, so its last day is
    # ahead, and tonight's tablet is still to take.
    def tonsillitis_course
      buy(@supplies[:co_amoxiclav], 30, 11.9)
      course = dose(alex, "Amoxicillin and clavulanic acid 875/125 mg", :pill, 875, "mg", { co_amoxiclav: 1 }, pill_count: 1,
                                                                                                               recurrence: { frequency: "daily", ends: Date.current + 14, slots: %w[08:00 20:00] })
      follow(course, done: 0.95, skipped: 0, late: 0.1, apart: true, force: { [ today, "08:00" ] => :done, [ today, "20:00" ] => :missed })
    end

    # Six weekly sessions for Sam's shoulder, paid one at a time; one called off.
    def physiotherapy
      first = Date.current + 3
      sessions = create(sam, Appointment.new(title: "Physiotherapy", start_time: "18:00", location: "Via Irnerio 12",
                                             notes: "Shoulder: bring the resistance band", starts_on: first,
                                             details_attributes: { kind: :medical, counterpart: "Studio Kinesis" }),
                        recurrence: { frequency: "weekly", ends: first + 35 })
      follow(sessions, done: 1, late: 0, force: { first + 21 => :cancelled },
                       after: ->(visit) { pay(visit, 45, on: visit.date, to: "Studio Kinesis", method: "cash") })
    end

    # A headache now and then: a tablet from the cabinet, no schedule.
    def painkiller
      tablet = dose(alex, "Ibuprofen 400 mg", :pill, 400, "mg", { ibuprofen: 1 }, pill_count: 1)
      tablet.first_occurrence.complete!
    end

    # A medication from today (a series, or a single dose) and what each dose
    # takes from stock: its plan (supply uses), drawn when a dose is taken.
    def dose(who, name, kind, quantity, unit, uses, therapy: nil, recurrence: nil, **details)
      supply_uses = uses.map { |supply, amount| { supply_id: @supplies.fetch(supply).id, quantity: amount } }
      medication = Medication.new(title: name, starts_on: Date.current, details_attributes: {
                                    kind: kind, quantity: quantity, unit: unit, **details, supply_uses_attributes: supply_uses
                                  })
      create(who, medication, recurrence: recurrence, collection: @therapies[therapy])
    end
  end
end
