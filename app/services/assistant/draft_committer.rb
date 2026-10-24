# frozen_string_literal: true

# Saves a complete draft as real records, atomically, through the same
# domain services the forms use (Occurrences::Create,
# Transactions::SetCost). What a kind saves, and in which order, is its
# builder's (Assistant::DraftBuilder#save!); the committer keeps what was
# saved and the calendar refreshes to run once it has all committed.
module Assistant
  class DraftCommitter
    # records: everything saved, in order; broadcasts: calendar refreshes to
    # run once the surrounding transaction has committed.
    Result = Data.define(:records, :broadcasts)

    def self.call(draft, profile:, builder: nil) = new(draft, profile:, builder:).call

    def initialize(draft, profile:, builder: nil)
      @draft = draft
      @profile = profile
      @builder = builder || DraftBuilder.for(draft, profile: profile)
      @saved = []
      @broadcasts = []
    end

    # Raises ActiveRecord::RecordInvalid or Pundit::NotAuthorizedError and
    # saves nothing on failure. Its transaction joins the caller's, so the
    # whole change set stays one.
    def call
      raise ArgumentError, "draft is not ready" unless @draft.ready?

      ActiveRecord::Base.transaction { @builder.save!(self) }
      Result.new(records: @saved, broadcasts: @broadcasts)
    end

    def keep(record) = @saved << record

    # The series' day cards are redrawn once everything has committed.
    def broadcast(event) = @broadcasts << -> { Calendar::DayCardBroadcaster.call(event: event) }

    # What the record cost, as the one payment about it (Transactions::SetCost).
    def attach_cost(about, date:, title:, counterparty:, status:, category: :healthcare)
      attrs = @builder.cost_attributes
      cost = Transactions::SetCost.call(
        about, date: date, title: title, status: status, category: category,
               amount: attrs["amount"], payment_method: attrs["payment_method"], currency: attrs["currency"],
               counterpart: attrs["counterparty"].presence || counterparty
      ).cost
      keep(cost)
      broadcast(cost.event)
    end
  end
end
