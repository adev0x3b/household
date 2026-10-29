# frozen_string_literal: true

module DemoBuilders
  # The demo installation's settings (config/deploy.demo.yml): its three
  # accounts open, and what a public playground mustn't do turned off.
  DEMO_SETTINGS = {
    "OPEN_ACCOUNTS" => "alex.demo,sam.demo,robin.demo", "UPLOADS" => "off", "PICTURES" => "off", "INVITATIONS" => "off",
    "PUSH_NOTIFICATIONS" => "off", "ASSISTANT_MESSAGES_PER_DAY" => "30", "BOOK_LOOKUPS_PER_DAY" => "50", "OUTGOING_MAIL" => "off"
  }.freeze

  # A bare demo household with its three members: enough for everything about
  # the demo but its data (Demo::Seeder builds that, in half a minute). No
  # owner, as the seeder makes it.
  def demo_household
    household = Household.create!(name: "Demo household", slug: Demo::Seeder::SLUG)
    %w[alex sam robin].each do |name|
      Profile.create!(household: household, username: "#{name}.demo", email: "#{name}@demo.example", password: "demo-household", first_name: name.capitalize)
    end
    household
  end

  # This copy is the demo installation for the block.
  def on_the_demo(&) = with_env(DEMO_SETTINGS, &)
end
