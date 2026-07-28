class CreatePms < ActiveRecord::Migration[7.1]
  def change
    create_table :pms do |t|
      t.string :name
      t.string :phone
      t.string :region
      t.string :locale

      t.timestamps
    end
  end
end
