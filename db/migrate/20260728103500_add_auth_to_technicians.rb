class AddAuthToTechnicians < ActiveRecord::Migration[7.1]
  def change
    add_column :technicians, :password_digest, :string
    add_column :technicians, :account_activated_at, :datetime
    add_column :technicians, :activation_token, :string
    add_column :technicians, :activation_token_expires_at, :datetime
    add_column :technicians, :login_code, :string
    add_column :technicians, :login_code_expires_at, :datetime
  end
end
