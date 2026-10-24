# frozen_string_literal: true

require "test_helper"

class Views::Occurrences::EventFieldsTest < ActiveSupport::TestCase
  test "the days of the week are named in the reader's language, the rule's own ticked" do
    weekly = Event.new(rrule: "FREQ=WEEKLY;BYDAY=MO,TH")

    assert_equal %w[Mon Tue Wed Thu Fri Sat Sun], fields(weekly).css(".event-fields__day-label span").map(&:text)
    assert_equal(%w[monday thursday], fields(weekly).css("input[checked]").map { _1["value"] })
    assert_equal "Lun", I18n.with_locale(:it) { fields(weekly) }.at_css(".event-fields__day-label span").text
  end

  test "a rule ice_cube can't read is reported and shows as a one-off" do
    frequency = nil
    assert_error_reported(ArgumentError) do
      frequency = fields(Event.new(rrule: "FREQ=SOMETIMES")).at_css("select[name='event[frequency]'] option[selected]")
    end

    assert_equal "none", frequency["value"]
  end

  private

  def fields(event)
    Nokogiri::HTML5.fragment(ApplicationController.render(Views::Occurrences::EventFields.new(event: event), layout: false))
  end
end
