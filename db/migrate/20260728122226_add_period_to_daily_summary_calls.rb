class AddPeriodToDailySummaryCalls < ActiveRecord::Migration[7.1]
  def change
    add_column :daily_summary_calls, :period, :string
  end
end
