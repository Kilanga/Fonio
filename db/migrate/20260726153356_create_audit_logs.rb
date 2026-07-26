class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_logs do |t|
      t.references :intervention, null: true, foreign_key: true
      t.references :technician, null: true, foreign_key: true
      t.string :actor
      t.string :event_type
      t.jsonb :details

      t.timestamps
    end
  end
end
