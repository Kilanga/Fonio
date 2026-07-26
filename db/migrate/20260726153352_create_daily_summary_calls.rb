class CreateDailySummaryCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :daily_summary_calls do |t|
      t.date :date
      t.string :pm_phone
      t.string :call_e_call_id
      t.string :call_status
      t.jsonb :raw_payload

      t.timestamps
    end
  end
end
