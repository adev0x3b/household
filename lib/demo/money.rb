# frozen_string_literal: true

module Demo
  # What comes in and goes out: two salaries and a student job, the bills
  # that return every month, and the spending in between. Everyone pays
  # their own part of the rent; what one pays for another is a transfer
  # between them, settled a few days later (the last ones still open).
  #
  # Groceries, meals out and healthcare costs aren't here: they come with
  # the shopping, the meals and the visits (Kitchen, Health).
  class Money < Part
    # who, title, kind, category, amount (or a range), paid by, to whom, day of the month, every n months
    MONTHLY = [
      [ :alex, "Salary", :income, :salary, 2850, :bank_transfer, "Northwind Studio", 27, 1 ],
      [ :sam, "Salary", :income, :salary, 2420, :bank_transfer, "Greenleaf Cooperative", 28, 1 ],
      [ :robin, "Bookshop pay", :income, :salary, 640..760, :bank_transfer, "Libreria Mondo", 10, 1 ],
      [ :alex, "Rent", :expense, :housing, 480, :bank_transfer, "Immobiliare Aurora", 1, 1 ],
      [ :sam, "Rent", :expense, :housing, 480, :bank_transfer, "Immobiliare Aurora", 1, 1 ],
      [ :robin, "Rent", :expense, :housing, 290, :bank_transfer, "Immobiliare Aurora", 2, 1 ],
      [ :alex, "Electricity", :expense, :utilities, 58..96, :bank_transfer, "Hera Luce", 12, 2 ],
      [ :alex, "Gas", :expense, :utilities, 28..74, :bank_transfer, "Hera Gas", 15, 1 ],
      [ :sam, "Internet", :expense, :utilities, 29.9, :card, "FibraNet", 5, 1 ],
      [ :alex, "Phone plan", :expense, :utilities, 7.99, :card, "Iliad", 8, 1 ],
      [ :sam, "Phone plan", :expense, :utilities, 9.99, :card, "Iliad", 8, 1 ],
      [ :robin, "Phone plan", :expense, :utilities, 7.99, :card, "Iliad", 9, 1 ],
      [ :alex, "Health insurance", :expense, :insurance, 42, :bank_transfer, "UniSalute", 20, 1 ],
      [ :sam, "Transit pass", :expense, :transportation, 39, :card, "TPER", 1, 1 ],
      [ :alex, "Streaming", :expense, :entertainment, 13.99, :card, "Netflix", 10, 1 ],
      [ :sam, "Music subscription", :expense, :entertainment, 10.99, :card, "Spotify", 12, 1 ],
      [ :sam, "Gym membership", :expense, :entertainment, 35, :card, "FitLab", 3, 1 ],
      [ :alex, "Savings", :expense, :savings, 550, :bank_transfer, "Savings account", 28, 1 ],
      [ :sam, "Savings", :expense, :savings, 350, :bank_transfer, "Savings account", 29, 1 ]
    ].freeze

    # days from today, who, title, kind, category, amount, paid by, to whom
    ONE_OFFS = [
      [ -168, :alex, "Logo for Studio Ferri", :income, :freelance, 620, :bank_transfer, "Studio Ferri" ],
      [ -161, :sam, "Waste tax", :expense, :taxes, 184, :bank_transfer, "Comune di Bologna" ],
      [ -149, :robin, "University fees, second instalment", :expense, :education, 420, :bank_transfer, "Università di Bologna" ],
      [ -131, :alex, "Illustrations for a book cover", :income, :freelance, 480, :bank_transfer, "Edizioni Calicanto" ],
      [ -118, :alex, "Summer flights", :expense, :entertainment, 412, :card, "Volotea" ],
      [ -97, :alex, "Car insurance", :expense, :insurance, 486, :bank_transfer, "Genertel" ],
      [ -93, :sam, "Performance bonus", :income, :bonus, 700, :bank_transfer, "Greenleaf Cooperative" ],
      [ -88, :sam, "Vet, yearly vaccines", :expense, :miscellaneous, 68, :card, "Clinica Veterinaria Reno" ],
      [ -66, :alex, "Holiday apartment", :expense, :entertainment, 540, :bank_transfer, "Casa Mare Otranto" ],
      [ -62, :sam, "Holiday car rental", :expense, :transportation, 210, :card, "Europcar" ],
      [ -47, :alex, "Refund for the cancelled ferry", :income, :refund, 64.5, :bank_transfer, "Adria Ferries" ],
      [ -38, :alex, "Website for Bottega Lume", :income, :freelance, 900, :bank_transfer, "Bottega Lume" ],
      [ -33, :robin, "University fees, first instalment", :expense, :education, 380, :bank_transfer, "Università di Bologna" ],
      [ -24, :alex, "Online course: motion design", :expense, :education, 89, :card, "Domestika" ],
      [ -16, :sam, "Shoes refund", :income, :refund, 74.9, :card, "Zalando" ],
      [ -6, :alex, "Condominium fees", :expense, :housing, 165, :bank_transfer, "Amministrazione Stabili Due Torri" ],
      [ 4, :alex, "Water bill", :expense, :utilities, 71.3, :bank_transfer, "Hera Acqua" ],
      [ 11, :alex, "Posters for Teatro Minimo", :income, :freelance, 350, :bank_transfer, "Teatro Minimo" ],
      [ 17, :sam, "Winter tyre change", :expense, :transportation, 60, :card, "Gommista Savena" ]
    ].freeze
    # Entered when the bill came, never paid: what the finance page says needs attention.
    UNPAID = [ "Condominium fees" ].freeze

    # What turns up in any month: category => [ [ title, to whom, low, high ], … ].
    EVERYDAY = {
      shopping: [ [ "New trainers", "Decathlon", 45, 90 ], [ "Towels and bed linen", "IKEA", 30, 75 ], [ "Jeans", "Zara", 35, 60 ],
                  [ "Phone case and cable", "MediaWorld", 18, 32 ], [ "Houseplants and pots", "Vivaio Sant'Orsola", 15, 48 ],
                  [ "Winter jacket", "OVS", 70, 140 ], [ "Kitchen knives", "Coin Casa", 40, 85 ] ],
      entertainment: [ [ "Cinema", "Cinema Lumière", 16, 24 ], [ "Concert tickets", "Estragon Club", 30, 70 ],
                       [ "Museum day", "MAMbo", 12, 20 ], [ "Board game", "Dadi e Mattoncini", 25, 45 ], [ "Books", "Libreria Mondo", 14, 38 ] ],
      transportation: [ [ "Fuel", "Q8", 42, 64 ], [ "Train to Milan", "Trenitalia", 28, 46 ], [ "Motorway toll", "Autostrade", 9, 22 ] ],
      miscellaneous: [ [ "Birthday present", "La Bottega del Regalo", 20, 55 ], [ "Hairdresser", "Salone Iride", 22, 48 ],
                       [ "Cat food and litter", "Arcaplanet", 24, 41 ] ]
    }.freeze
    EVERYDAY_PER_WEEK = { shopping: 0.5, entertainment: 0.7, transportation: 0.9, miscellaneous: 0.6 }.freeze

    # days from today, who paid, for whom, title, category, amount, settled after how many days (nil: still open)
    BETWEEN_US = [
      [ -143, :alex, :sam, "Concert ticket for Sam", :entertainment, 38, 4 ],
      [ -109, :sam, :alex, "Alex's half of the boiler repair", :housing, 72.5, 6 ],
      [ -64, :alex, :robin, "Robin's share of the holiday", :entertainment, 180, 9 ],
      [ -52, :sam, :robin, "Robin's phone screen repair", :miscellaneous, 89, 12 ],
      [ -19, :robin, :alex, "Alex's parcel, customs fee", :miscellaneous, 18.4, nil ],
      [ -8, :alex, :sam, "Sam's half of the washing machine repair", :housing, 65, nil ]
    ].freeze

    private

    def setup
      MONTHLY.each { |bill| monthly(*bill) }
      ONE_OFFS.each { |days, who, title, *rest| one_off(send(who), title, *rest, on: today + days, paid: UNPAID.exclude?(title)) }
      BETWEEN_US.each { |transfer| between_us(*transfer) }
    end

    def daily(day)
      EVERYDAY_PER_WEEK.each do |category, per_week|
        next unless chance?(per_week / 7.0)

        title, payee, low, high = pick(EVERYDAY.fetch(category))
        one_off(pick([ alex, alex, sam, sam, robin ]), title, :expense, category, amount(low, high), pick(%i[card card cash]), payee, on: day)
      end
    end

    def monthly(who, title, kind, category, price, method, payee, day_of_month, interval)
      bill = create(send(who), build(title, kind, category, price, method, payee, next_month_day(start, day_of_month)),
                    recurrence: { frequency: "monthly", interval: interval })
      # A bill that changes month to month: that month's amount is the day's own.
      varies = price.is_a?(Range) ? ->(day) { day.write_details!(amount: amount(price.begin, price.end)) } : nil
      follow(bill, done: kind == :income ? 1 : 0.985, skipped: 0, late: kind == :income ? 0 : 0.06, before: varies)
    end

    def one_off(who, title, kind, category, price, method, payee, on:, paid: true)
      at(entered(on, rng.rand(0..4))) do
        bill = create(who, build(title, kind, category, price, method, payee, on))
        at(on) { bill.first_occurrence.complete! } if paid
      end
    end

    # One pays for the other (the other owes it), then the other pays it back.
    def between_us(days, payer, debtor, title, category, price, settled_after)
      paid_on = today + days
      at(paid_on) { transfer(send(payer), send(debtor), title, category, price, paid_on) }
      return unless settled_after

      at(paid_on + settled_after) do
        transfer(send(debtor), send(payer), "Paid back: #{title.sub(/\A\w/, &:downcase)}", category, price, paid_on + settled_after)
      end
    end

    # One payment, two readers: the payer's expense is the other's income
    # (Transaction#kind_for) — there is nothing to copy to the other side.
    def transfer(from, to, title, category, price, date)
      payment = create(from, Transaction.new(title: title, starts_on: date, details_attributes: {
                                               kind: :expense, category: category, amount: price, currency: alex.household.currency, payment_method: :bank_transfer, counterparty_profile: to
                                             }))
      payment.first_occurrence.complete!
    end

    def build(title, kind, category, price, method, payee, date)
      price = amount(price.begin, price.end) if price.is_a?(Range)
      Transaction.new(title: title, starts_on: date, details_attributes: {
                        kind: kind, category: category, amount: price, currency: alex.household.currency, payment_method: method, counterparty: payee
                      })
    end
  end
end
