class CreateTechnicians < ActiveRecord::Migration[7.1]
  def change
    create_table :technicians do |t|
      t.string :name
      t.string :phone
      t.boolean :consent_given, default: false, null: false
      t.datetime :consent_given_at

      t.timestamps
    end
    add_index :technicians, :phone, unique: true
  end
end
