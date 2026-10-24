# frozen_string_literal: true

module AssistantEval
  module Checks
    # Named OneAppointment, not Appointment, so that nothing in Checks takes
    # it for the model.
    class OneAppointment < Base
      def self.key = "appointment"
      def self.argument = "One appointment: counterpart (or provider) and date, plus any of kind / time / status / fee / fee_status / fee_paid_by"
      def self.example = { "counterpart" => "Moretti", "date" => "2026-09-25", "time" => "10:00", "fee" => 50 }

      def call(want)
        who = want["counterpart"] || want["provider"]
        appointment = find(who, Date.parse(want["date"].to_s))
        return "appointment: none with #{who} on #{want["date"]}" if appointment.nil?

        problems = problems_of(appointment, want)
        "appointment: #{problems.join(", ")}" if problems.any?
      end

      private

      # "doctor Moretti" is Moretti: the counterpart's words must include the expected ones.
      def find(who, date)
        wanted = who.to_s.downcase.scan(/[[:alnum:]]+/)
        records.appointments.find { |a| (wanted - a.details.counterpart.to_s.downcase.scan(/[[:alnum:]]+/)).empty? && a.date == date }
      end

      def problems_of(appointment, want)
        fee = appointment.costs.first
        problems = []
        problems << "kind #{appointment.details.kind}" if want["kind"] && appointment.details.kind != want["kind"].to_s
        problems << "time #{appointment.formatted_start_time.inspect}" if want["time"] && appointment.formatted_start_time != want["time"]
        problems << "status #{appointment.status}" if want["status"] && appointment.status != want["status"]
        problems << "fee #{amount(fee).to_f}" if want["fee"] && !same_number?(amount(fee), want["fee"])
        problems << "fee_status #{fee&.status}" if want["fee_status"] && fee&.status != want["fee_status"]
        problems << "fee_paid_by #{paid_with(fee)}" if want["fee_paid_by"] && paid_with(fee) != want["fee_paid_by"]
        problems
      end
    end
  end
end
