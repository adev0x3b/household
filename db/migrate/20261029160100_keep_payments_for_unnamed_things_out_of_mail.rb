# frozen_string_literal: true

# The payments already about something a mail doesn't name, as the kinds
# answer today (Event.named_in_mail?, Costable#named_in_mail?): a day or a
# series of any kind but a task or a meal, and a supply bought; groceries
# are named. A payment whose thing was deleted before this can't say what
# it was about; one filed under healthcare, as the fees of every such kind
# are but a visit's that wasn't medical, is kept out too, even one typed by
# hand, which errs on the private side.
class KeepPaymentsForUnnamedThingsOutOfMail < ActiveRecord::Migration[8.1]
  # The tables as they are now, without the models' callbacks and types.
  class Details < ActiveRecord::Base
    self.table_name = "transaction_details"
  end

  class Event < ActiveRecord::Base
    self.table_name = "events"
    self.inheritance_column = nil
  end

  class Occurrence < ActiveRecord::Base
    self.table_name = "occurrences"
  end

  NAMED_KINDS = %w[Task Meal].freeze
  # Transaction::Details.categories["healthcare"].
  HEALTHCARE = 8

  def up
    unnamed_series = Event.where.not(type: NAMED_KINDS).select(:id)
    unnamed_days = Occurrence.where(event_id: unnamed_series).select(:id)
    about_unnamed = Details.where(about_type: "SupplyPurchase")
      .or(Details.where(about_type: "Event", about_id: unnamed_series))
      .or(Details.where(about_type: "Occurrence", about_id: unnamed_days))
      .or(Details.where(about_type: nil, category: HEALTHCARE))
    about_unnamed.update_all(named_in_mail: false)
  end

  # The marks stay: the column goes with the previous migration.
  def down; end
end
