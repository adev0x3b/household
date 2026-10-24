# frozen_string_literal: true

require "test_helper"

# How someone writes a time of the day ("dinner", "8pm", "20:00", "CV") as
# the slot it is: an anchor's code, or "HH:MM".
class Events::TimesOfDayTest < ActiveSupport::TestCase
  test "anchors by their code or their words, clock times however written, nothing else" do
    { "CV" => "CV", "dinner" => "CV", "20:00" => "20:00", "8" => "08:00", "8pm" => "20:00", "8.30 pm" => "20:30",
      "12am" => "00:00", "12pm" => "12:00", "20h" => "20:00" }.each do |written, slot|
      assert_equal slot, Events::TimesOfDay.code_for(written), written
    end
    [ "", " ", "25:00", "8:75", "teatime soon" ].each { assert_nil Events::TimesOfDay.code_for(_1), _1.inspect }
  end
end
