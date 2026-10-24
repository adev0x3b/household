# frozen_string_literal: true

class AddStartTimeToAppointments < ActiveRecord::Migration[8.1]
  def change
    add_column :appointments, :start_time, :time
  end
end
