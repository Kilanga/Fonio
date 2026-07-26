class CreateCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :calls do |t|
      t.references :intervention, null: false, foreign_key: true
      t.string :call_type
      t.string :call_status
      t.integer :attempt, default: 1
      t.string :call_e_call_id
      t.jsonb :raw_payload
      t.boolean :has_started
      t.boolean :has_issue
      t.string :severity
      t.boolean :needs_help
      t.datetime :revised_eta
      t.string :report_status
      t.string :edit_token
      t.datetime :edit_token_expires_at
      t.text :work_completed
      t.text :equipment_used
      t.text :anomalies
      t.text :recommendations
      t.integer :actual_duration_minutes
      t.boolean :is_anomaly_severe

      t.timestamps
    end
    add_index :calls, :edit_token, unique: true
    add_index :calls, :call_e_call_id
  end
end
