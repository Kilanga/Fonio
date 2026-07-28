class AddAcceptedAtToInterventions < ActiveRecord::Migration[7.1]
  def change
    add_column :interventions, :accepted_at, :datetime
  end
end
