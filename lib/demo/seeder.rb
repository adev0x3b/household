# frozen_string_literal: true

require "active_support/testing/time_helpers"

# Builds the demo household: three people and six months of made-up life,
# ending today. Nothing is inserted as finished history: the seeder lives
# through the period one day at a time, with the clock set to that day, and
# does what the people would have done through the same code the app runs
# (Occurrences::Create, Occurrence#complete!, GroceryListItem#check!,
# Transactions::SetCost…). So stock levels, batches, pantry quantities,
# what each housemate owes the other and timestamps all agree with each
# other, and every dashboard has a past to compare with.
#
#   Demo::Seeder.call            # or: bin/rails demo:seed
#
# It always starts over: an existing demo household (the one with SLUG,
# Demo::Seeder.household) is deleted first (Households::Destroy). The same
# day gives the same household (the random choices are seeded with the
# date). Each part of the household's life is a Demo::Part: Chores, Money,
# Health, Kitchen, Library, Paperwork, Partners, Talk.
#
# The household has no owner: on the demo installation its accounts are
# everyone's (Platform.open_accounts), and an owner could remove the others.
module Demo
  class Seeder
    DAYS = 182
    PARTS = [ Chores, Money, Health, Kitchen, Library, Paperwork, Partners, Talk ].freeze
    NAME = "Demo household"
    SLUG = "demo"
    # Unread on the bell when the demo opens: what was shared in the last days.
    UNREAD_DAYS = 3
    # What a share of each kind of thing is kept in (a series of any kind
    # is an Event).
    attr_reader :today, :start, :rng, :household, :alex, :sam, :robin

    def self.call(...) = new(...).call

    # The demo household, where there is one (the rebuild, demo:remove, db/seeds.rb).
    def self.household = Household.find_by(slug: SLUG)

    def initialize(today: Date.current, password: Platform.demo_password, out: $stdout)
      @today = today
      @start = today - DAYS
      @password = password
      @out = out
      @rng = Random.new(today.jd)
      @clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
    end

    def call
      @out.puts "🏡 Seeding the demo household (#{start} → #{today})…"
      self.class.household&.then { |old| Households::Destroy.call(old) }

      ActiveRecord::Base.transaction do
        on(start) { move_in }
        parts = PARTS.map { |part| part.new(self) }
        (start..today).each { |day| on(day) { parts.each { |part| part.day(day) } } }
        on(today) { parts.each(&:finish) }
        leave_latest_news_unread
      end

      report
      household
    ensure
      @clock.travel_back
    end

    def chance?(probability) = rng.rand < probability

    def pick(choices) = choices[rng.rand(choices.size)]

    # An amount between two, to the cent.
    def amount(low, high) = rng.rand(low.to_f..high.to_f).round(2)

    # How far through the six months `day` is, 0 to 1.
    def progress(day) = ((day - start).to_f / DAYS).clamp(0, 1)

    # Shares it with a housemate, who hears about it under the bell (read a
    # few hours later, like most notifications are — `read_after` says how
    # long, or the dice do).
    def share(thing, with:, read_after: nil)
      raise ArgumentError, "can't share a #{thing.class}" unless thing.is_a?(Shareable)

      thing.shares.create!(profile: with)
      Notification.create!(profile: with, actor: thing.profile, kind: :shared, subject: thing, subject_title: thing.shared_name,
                           read_at: Time.current + (read_after || rng.rand(1..9).hours))
    end

    private

    # Midday, so nothing lands on the wrong side of midnight in any time zone.
    def on(day, &block) = @clock.travel_to(day.in_time_zone.change(hour: 12), &block)

    def move_in
      @household = Household.create!(name: NAME, slug: SLUG)
      @alex = member("alex", "Alex", "Rivera", :female)
      @sam = member("sam", "Sam", "Okafor", :male)
      @robin = member("robin", "Robin", "Rivera", :non_binary)
    end

    def member(name, first_name, last_name, gender)
      # Confirmed addresses, as a household that uses mail has: a development
      # copy with a relay shows and sends what theirs would, and the demo,
      # whose mail is off, sends nothing.
      profile = Profile.create!(
        household: household, username: "#{name}.demo", email: "#{name}@demo.example", email_confirmed_at: Time.current,
        password: @password, first_name: first_name, last_name: last_name, gender: gender, role: :user
      )
      Profiles::Join.call(profile)
    end

    def leave_latest_news_unread
      Notification.where(profile_id: household.profiles.select(:id), created_at: (today - UNREAD_DAYS).beginning_of_day..)
        .update_all(read_at: nil)
    end

    # What was made: the series of each kind and the days kept of them
    # (done, skipped, changed — a day nothing happened to has no row).
    def report
      events = Event.where(profile_id: household.profiles.select(:id))
      @out.puts "  ✔ #{household.name}: #{household.profiles.order(:id).pluck(:username).join(", ")} (password: #{@password})"
      Event.types.each do |kind|
        series = events.of_type(kind)
        @out.puts "  ✔ #{series.count} #{kind.model_name.human.downcase.pluralize} " \
                  "(#{Occurrence.of_type(kind).where(event_id: series.select(:id)).count} days kept)"
      end
      @out.puts "  ✔ #{Collection.where(profile: household.profiles).count} collections"
      @out.puts "  ✔ #{Recipe.where(profile: household.profiles).count} recipes, " \
                "#{GroceryList.where(profile: household.profiles).count} grocery lists, " \
                "#{IngredientPurchase.where(profile: household.profiles).count} pantry purchases, " \
                "#{SupplyPurchase.where(profile: household.profiles).count} supply purchases"
      @out.puts "  ✔ #{Book.where(profile: household.profiles).count} books (#{Book.where(profile: household.profiles).read.count} read)"
      @out.puts "  ✔ #{Upload.where(profile: household.profiles).count} files (#{UploadShare.where(upload: Upload.where(profile: household.profiles)).count} shared)"
      @out.puts "  ✔ #{Message.where(sender: household.profiles).count} messages in #{Conversation.where(household: household).count} conversations"
    end
  end
end
