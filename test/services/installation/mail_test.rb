# frozen_string_literal: true

require "test_helper"

# The mail card of /admin/settings and step of the first setup: the switch,
# the relay and the budgets, checked and written on the settings' row.
class Installation::MailTest < ActiveSupport::TestCase
  test "starts from what is in use, and leaves a relay's field the environment fills empty" do
    Platform::Setting.create!(smtp_host: "saved.example", mails_per_hour: 3)
    mail = with_relay { Installation::Mail.current }

    assert mail.outgoing_mail
    assert_equal [ 3, 40, 20 ], [ mail.mails_per_hour, mail.mails_per_day, mail.reminder_mails_per_day ]
    assert_equal "saved.example", mail.smtp_host
    assert_nil mail.smtp_username, "the environment's is the field's placeholder, never a value saved with the rest"
    assert_nil mail.smtp_password
  end

  test "checks the relay's fields, and keeps each budget at least what it may be" do
    mail = Installation::Mail.current.assign(smtp_host: "https://relay.example", smtp_port: "smtp", smtp_tls: "ssl", mail_from: "household",
                                             mails_per_hour: "1", mails_per_day: "5", reminder_mails_per_day: "-1")

    assert_not mail.valid?
    assert_equal %i[mail_from mails_per_day mails_per_hour reminder_mails_per_day smtp_host smtp_port smtp_tls], mail.errors.attribute_names.sort
    assert_predicate Installation::Mail.current.assign(smtp_host: "relay.example", smtp_port: "465", smtp_tls: "tls", mail_from: "a@b.example",
                                                       mails_per_hour: "2", mails_per_day: "6", reminder_mails_per_day: "0"), :valid?
  end

  test "a login is never sent in the clear: no encryption takes no username or password" do
    mail = Installation::Mail.current.assign(smtp_host: "relay.example", smtp_tls: "none", smtp_username: "household", smtp_password: "pw")

    assert_not mail.valid?
    assert mail.errors.of_kind?(:smtp_tls, :login_in_clear)
    assert_predicate Installation::Mail.current.assign(smtp_host: "localhost", smtp_tls: "none"), :valid?
  end

  test "writes everything on the row, and the password only when one was typed" do
    setting = Platform::Setting.create!(smtp_password: "kept-secret", mails_per_hour: 3)

    Installation::Mail.current.assign(outgoing_mail: "0", smtp_host: " relay.example ", smtp_port: "465", smtp_tls: "tls", smtp_username: "household",
                                      smtp_password: " ", mail_from: "household@household.example", mails_per_hour: "", mails_per_day: "50",
                                      reminder_mails_per_day: "0").apply_to(setting).save!

    setting.reload
    assert_not setting.outgoing_mail
    assert_equal [ "relay.example", 465, "tls", "household", "household@household.example", "kept-secret" ],
                 [ setting.smtp_host, setting.smtp_port, setting.smtp_tls, setting.smtp_username, setting.mail_from, setting.smtp_password ]
    assert_equal [ 6, 50, 0 ], [ Platform.mails_per_hour, Platform.mails_per_day, Platform.reminder_mails_per_day ], "an empty budget is its default"

    Installation::Mail.current.assign(smtp_password: "new-secret").apply_to(setting).save!
    assert_equal "new-secret", setting.reload.smtp_password
  end
end
