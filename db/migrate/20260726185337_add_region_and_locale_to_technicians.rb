class AddRegionAndLocaleToTechnicians < ActiveRecord::Migration[7.1]
  def change
    add_column :technicians, :region, :string
    add_column :technicians, :locale, :string
  end
end
