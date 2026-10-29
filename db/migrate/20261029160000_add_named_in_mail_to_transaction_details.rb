# frozen_string_literal: true

# Whether a reminder mail may name a payment by its title
# (Transaction#reminder_mail_thing): not once it is about something a mail
# doesn't name, and still not after that thing is deleted and the payment
# kept. The payments already about one are marked by the next migration.
class AddNamedInMailToTransactionDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :transaction_details, :named_in_mail, :boolean, null: false, default: true
  end
end
