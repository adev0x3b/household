# frozen_string_literal: true

require "test_helper"

# Links::Page reads what the Links page lists, for one viewer or for
# everyone a change is pushed to, in the same few queries.
class Links::PageTest < ActiveSupport::TestCase
  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    link!(@alice, @bob)
    @asked = Link.create!(requester: @carol, addressee: @alice)
  end

  test "each viewer's page: their links, the requests both ways, the housemates left to link with" do
    page = Links::Page.new([ @alice, @bob, @carol ])

    assert_equal([ @bob ], page.links(@alice).map { _1.partner_of(@alice) })
    assert_equal([ @alice ], page.links(@bob).map { _1.partner_of(@bob) })
    assert_empty page.links(@carol)
    assert_equal [ @asked ], page.incoming(@alice)
    assert_equal [ @asked ], page.outgoing(@carol)
    assert_empty page.housemates(@alice), "Bob is linked, Carol asked"
    assert_equal [ @carol ], page.housemates(@bob)
    assert_equal [ @bob ], page.housemates(@carol)
    assert_not_includes page.housemates(@bob), profiles(:outsider)
  end

  test "three viewers are read in the queries one is" do
    one = queries_in { read(Links::Page.new([ @alice ]), [ @alice ]) }
    three = queries_in { read(Links::Page.new([ @alice, @bob, @carol ]), [ @alice, @bob, @carol ]) }

    assert_equal one, three
  end

  private

  def read(page, viewers)
    viewers.each { |viewer| %i[approvals requests incoming outgoing links housemates].each { page.public_send(_1, viewer) } }
  end

  # Every query, the query cache off: a viewer read twice would show.
  def queries_in(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block) }
    count
  end
end
