# frozen_string_literal: true

module Assistant
  class GetRecordTool < Tool
    description "Shows one record in detail with what is linked to it. For an upcoming occurrence with no id, pass event_id and date."
    parameter :type, description: "Record type, e.g. appointment or therapy"
    parameter :id, type: :integer, description: "Record id", required: false
    parameter :event_id, type: :integer, description: "Series id, for an upcoming occurrence", required: false
    parameter :date, description: "ISO date of that occurrence", required: false

    def execute(type:, id: nil, event_id: nil, date: nil)
      record = locate(type, id:, event_id:, date:)
      summarize(record).merge(linked(record)).compact
    end

    private

    def linked(record)
      case record
      when Collection
        purchases = SupplyPurchase.accessible_by(profile).where(collection: record).order(purchased_on: :desc).limit(10)
        { recent_purchases: purchases.map { |p| summarize(p) } }
      when Supply
        { recent_purchases: SupplyPurchase.accessible_by(profile).where(supply: record).order(purchased_on: :desc).limit(5).map { |p| summarize(p) } }
      else
        return {} unless record.persisted? && record.respond_to?(:costs) && !(record.is_a?(Occurrence) && !record.event.costable?)

        { costs: record.costs.map { |cost| summarize(cost) } }
      end
    end
  end
end
