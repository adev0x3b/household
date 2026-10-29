# frozen_string_literal: true

require "test_helper"

# The relay mail goes out through: each field as the admin saved it, else
# the environment's, and what keeps mail from going out.
class Emails::RelaySettingsTest < ActiveSupport::TestCase
  SETTINGS = { host: "relay.example", port: "587", username: nil, password: nil, tls: "starttls", from: "household@household.example" }.freeze

  test "each field is the saved one, else the environment's" do
    Platform::Setting.create!(smtp_port: 2525, smtp_password: "saved-password")
    relay = with_relay { Emails::RelaySettings.current }

    assert_equal [ "relay.example", 2525, "household", "saved-password" ], [ relay.host, relay.port, relay.username, relay.password ]
    assert_equal "household@household.example", relay.from
    assert_predicate relay, :configured?
  end

  test "the environment's login goes only to the environment's relay: one saved on the page gets the login saved with it" do
    Platform::Setting.create!(smtp_host: "saved.example")
    relay = with_relay { Emails::RelaySettings.current }
    assert_equal [ "saved.example", nil, nil ], [ relay.host, relay.username, relay.password ]

    Platform.saved.update!(smtp_username: "saved-user", smtp_password: "saved-password")
    relay = with_relay { Emails::RelaySettings.current }
    assert_equal [ "saved-user", "saved-password" ], [ relay.username, relay.password ]

    Platform.saved.update!(smtp_host: "RELAY.example", smtp_username: nil, smtp_password: nil)
    relay = with_relay { Emails::RelaySettings.current }
    assert_equal [ "household", "relay-password" ], [ relay.username, relay.password ], "the environment's own relay, however it is written"
  end

  test "says where each field in use comes from, the environment's login only for the environment's relay" do
    sources = -> { %i[smtp_host smtp_username smtp_password mail_from].map { Emails::RelaySettings.source(_1) } }

    with_relay do
      assert_equal %i[env env env env], sources.call
      Platform::Setting.create!(smtp_host: "saved.example", smtp_password: "saved-password")
      assert_equal [ :saved, nil, :saved, :env ], sources.call
    end
    assert_equal [ :saved, nil, :saved, nil ], sources.call
  end

  test "a server and a sender are all it needs: STARTTLS on 587, and no login without a username" do
    relay = Emails::RelaySettings.new(**SETTINGS, port: nil, username: " ", tls: nil)

    assert_predicate relay, :configured?
    assert_equal({ address: "relay.example", port: 587, domain: "household.example", user_name: nil, password: nil, authentication: nil,
                   enable_starttls: :always }, relay.smtp)
  end

  test "a port left empty is the one its encryption is offered on" do
    port = ->(tls) { Emails::RelaySettings.new(**SETTINGS, port: " ", tls: tls).port }

    assert_equal [ 587, 465, 25 ], [ port.call("starttls"), port.call("tls"), port.call("none") ]
  end

  test "says what keeps mail from going out, the first thing first" do
    problem = ->(**changes) { Emails::RelaySettings.new(**SETTINGS, **changes).problem }

    assert_nil problem.call
    assert_equal :host, problem.call(host: " ", from: nil)
    assert_equal :from, problem.call(from: "household")
    assert_equal :port, problem.call(port: "smtp")
    assert_equal :port, problem.call(port: "70000")
    assert_equal :tls, problem.call(tls: "ssl")
    assert_nil problem.call(tls: "none")
    assert_equal :login_in_clear, problem.call(tls: "none", username: "household", password: "relay-password")
    assert_equal :login_in_clear, problem.call(tls: "none", password: "relay-password")
  end

  test "TLS from the first byte, or none for a catcher on the same machine; never STARTTLS left to chance" do
    smtp = ->(tls) { Emails::RelaySettings.new(**SETTINGS, port: 465, username: "household", password: "pw", tls: tls).smtp }

    assert_equal [ true, :plain ], smtp.call("TLS").values_at(:tls, :authentication)
    assert_equal [ false, false ], smtp.call("none").values_at(:enable_starttls, :enable_starttls_auto)
    assert_equal :always, smtp.call(nil)[:enable_starttls]
  end
end
