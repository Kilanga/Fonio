class CreateInterventions < ActiveRecord::Migration[7.1]
  def change
    create_table :interventions do |t|
      t.references :technician, null: false, foreign_key: true
      t.string :site_name
      t.string :site_address
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :expected_end_time
      t.datetime :reminder_sent_at
      t.datetime :completed_at
      t.integer :status, default: 0, null: false

      t.timestamps
    end
    add_index :interventions, :status
    add_index :interventions, :site_name
  end
end
