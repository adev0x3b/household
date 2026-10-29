# frozen_string_literal: true

# Mail in tests: a relay set as a destination sets it, and the mail a drain
# hands it, which never leaves the test.
module MailBuilders
  RELAY = { "SMTP_HOST" => "relay.example", "SMTP_PORT" => "587", "SMTP_USERNAME" => "household", "SMTP_PASSWORD" => "relay-password",
            "MAIL_FROM" => "household@household.example" }.freeze

  # A relay set for the block (Emails::RelaySettings); a value given as nil
  # is unset.
  def with_relay(overrides = {}, &) = with_env(RELAY.merge(overrides), &)

  # The mail handed to the relay in the block, each as the drain made it.
  # `answer` stands for the relay instead: given the mail, it raises what
  # the relay would answer.
  def relayed(answer: ->(_mail) { })
    handed = []
    relay = lambda do |mail|
      handed << mail
      answer.call(mail)
    end
    swapping(Emails::Relay, :perform, relay) { yield }
    handed
  end
end
