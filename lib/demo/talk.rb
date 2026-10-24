# frozen_string_literal: true

module Demo
  # What the three say to each other: the household's conversation (renamed
  # by Sam early on), and what Alex and Sam, Alex and Robin keep between
  # them. A few lines most weeks, more around what the other parts set up
  # (a dinner, a birthday, the car). The last ones, from last night, are
  # still unread by Alex, whose account the demo opens. Nothing is said
  # today: the demo is rebuilt in the small hours, and a line dated later
  # in the day would sit in the future until its minute came.
  #
  # Every line goes through Messages::Send, the way the composer sends it —
  # with the clock set to its minute, and without telling anyone (the bell
  # is told once, at the end, about what Alex hasn't read).
  class Talk < Part
    include ActiveSupport::Testing::TimeHelpers

    # days ago, who, "hh:mm", words, reactions [ [ who, emoji ], … ]
    HOUSEHOLD = [
      [ 181, :alex, "19:40", "We're in! Boxes everywhere, but we're in 📦", [ [ :sam, "🎉" ], [ :robin, "🎉" ] ] ],
      [ 181, :sam, "19:42", "Pizza tonight, nobody is finding the pans" ],
      [ 180, :robin, "08:15", "Who took the good scissors" ],
      [ 180, :alex, "08:20", "Kitchen, second drawer. Mine now." ],
      [ 172, :sam, "18:05", "Recycling goes out Tuesday night, I put it in the calendar" ],
      [ 160, :alex, "13:10", "Plumber's coming Thursday morning for the tap, someone has to be in" ],
      [ 160, :robin, "13:12", "I'm home till 11" ],
      [ 160, :sam, "13:30", "I'll take the afternoon then", [ [ :alex, "🙏" ] ] ],
      [ 147, :alex, "20:02", "Parking permit renewed. 60 € and an hour of my life.", [ [ :sam, "😂" ] ] ],
      [ 133, :robin, "22:15", "Signed up for the autumn exams 😬", [ [ :alex, "❤️" ], [ :sam, "👍" ] ] ],
      [ 120, :sam, "12:45", "Fridge is looking sad. Grocery list is open if you want anything" ],
      [ 120, :alex, "12:50", "Added yoghurt and the good coffee" ],
      [ 113, :alex, "21:30", "Flights booked! 🏖️", [ [ :sam, "🎉" ], [ :robin, "😮" ] ] ],
      [ 98, :sam, "07:50", "Car's making the noise again" ],
      [ 98, :alex, "07:55", "Which noise" ],
      [ 98, :sam, "07:56", "The noise" ],
      [ 84, :alex, "17:20", "Cat sitter found for August, she's lovely", [ [ :robin, "❤️" ] ] ],
      [ 70, :robin, "09:30", "Don't forget my charger is in the car" ],
      [ 55, :sam, "11:00", "Fridge emptied, bins out, keys with the neighbour. Go go go" ],
      [ 41, :alex, "16:40", "Sorted the holiday photos. 600 of them. Half are the cat." ],
      [ 36, :sam, "19:15", "Smoke alarm batteries changed, it stopped chirping at 3 am", [ [ :alex, "🙏" ], [ :robin, "🙏" ] ] ],
      [ 26, :robin, "14:05", "Transit card renewed, thanks for the money" ],
      [ 17, :alex, "10:30", "Landlord says the intercom guy comes next week" ],
      [ 12, :sam, "18:50", "Radiators bled. The hallway one was all air" ],
      [ 6, :alex, "20:10", "Dinner on the 13th for Robin's birthday, who's cooking?" ],
      [ 6, :sam, "20:12", "Me. Lasagna. No arguments.", [ [ :robin, "❤️" ], [ :alex, "👍" ] ] ],
      [ 3, :sam, "09:05", "Meter readings sent, photos are in the app" ],
      [ 1, :alex, "19:00", "Parcel went back, they said 5 days for the refund" ],
      [ 1, :sam, "21:40", "Tyre change booked for Friday, 8:30" ],
      [ 1, :robin, "21:52", "Can someone drive me to the internship interview on Monday 🙏" ]
    ].freeze

    ALEX_SAM = [
      [ 150, :sam, "22:30", "Robin asleep?" ],
      [ 150, :alex, "22:31", "Finally. Tea?" ],
      [ 150, :sam, "22:31", "Tea.", [ [ :alex, "❤️" ] ] ],
      [ 90, :alex, "12:15", "Did you see the electricity offer? 20 % less than what we pay" ],
      [ 90, :sam, "12:40", "Switch it. I trust you with the paperwork" ],
      [ 30, :sam, "16:00", "Ordered Robin's school books, 118 €. Added it to the finances" ],
      [ 30, :alex, "16:05", "Thanks ❤️" ],
      [ 7, :alex, "21:20", "Present ideas for Robin? I have nothing" ],
      [ 7, :sam, "21:35", "The headphones they keep mentioning. I'll get them, you do the cake" ],
      [ 1, :sam, "22:10", "Tax paperwork: the folder is on your desk, the bank statements are in it" ],
      [ 1, :sam, "22:11", "Call me if anything is missing" ]
    ].freeze

    ALEX_ROBIN = [
      [ 133, :robin, "22:20", "Did I do the right thing with the exam session" ],
      [ 133, :alex, "22:25", "Yes. One step at a time. Proud of you.", [ [ :robin, "❤️" ] ] ],
      [ 60, :alex, "15:30", "Laundry's been in the machine since yesterday 👀" ],
      [ 60, :robin, "15:45", "ON IT" ],
      [ 5, :robin, "17:00", "Can you check my internship application before I send it?" ],
      [ 5, :alex, "17:20", "Send it over, I'll read it tonight", [ [ :robin, "🙏" ] ] ],
      [ 1, :robin, "21:55", "And thank you for the dinner thing, Sam told me 🎂" ]
    ].freeze

    RENAMED = "Casa Rivera-Okafor"

    # A line under Alex's bell for each conversation with news since Alex last read it.
    def finish
      [ @household_conversation, @alex_sam, @alex_robin ].each do |conversation|
        newest = conversation.messages.newest_first.first
        next if newest.nil? || newest.sender_id == alex.id || conversation.reload.unread_count_for(alex).zero?

        Notification.create!(profile: alex, actor: newest.sender, kind: :message_received, subject: conversation, subject_title: conversation.title_for(alex),
                             data: { "scope" => conversation.kind, "detail" => newest.line, "unread" => conversation.unread_count_for(alex) },
                             created_at: newest.created_at, updated_at: newest.created_at)
      end
    end

    private

    def setup
      @rng = Random.new(start.jd + 17)
      @household_conversation = Conversation.household_conversation(alex.household)
      @alex_sam = Conversation.direct_between(alex, sam)
      @alex_robin = Conversation.direct_between(alex, robin)

      script(@household_conversation, HOUSEHOLD)
      script(@alex_sam, ALEX_SAM)
      script(@alex_robin, ALEX_ROBIN)
      at(ago(179)) { @household_conversation.update!(name: RENAMED) }
    end

    # Everyone reads everything by the end of each day, but Alex, who
    # still has last night's messages to read when the demo opens.
    def daily(day)
      [ @household_conversation, @alex_sam, @alex_robin ].each do |conversation|
        newest = conversation.messages.newest_first.first or next
        conversation.conversation_participants.each do |participant|
          next if day >= today - 1 && participant.profile_id == alex.id

          participant.read_up_to!(newest)
        end
      end
    end

    def script(conversation, lines)
      lines.each do |days, who, clock, words, reactions|
        at(ago(days)) do
          hour, minute = clock.split(":").map(&:to_i)
          travel_to(Time.current.change(hour: hour, min: minute)) do
            message = Messages::Send.call(conversation: conversation, sender: send(who), body: words, client_id: SecureRandom.uuid, notify: false)
            reactions.to_a.each { |reactor, emoji| message.message_reactions.create!(profile: send(reactor), emoji: emoji) }
          end
        end
      end
    end
  end
end
