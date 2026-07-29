# The check-in call script (see CallScripts.check_in) already asks the
# technician what kind of issue they have and what help they need — but
# there was nowhere to store the answer, so it was silently discarded on
# every webhook. See app/controllers/webhooks/call_e_controller.rb.
class AddIssueDetailsToCalls < ActiveRecord::Migration[7.1]
  def change
    add_column :calls, :issue_type, :string
    add_column :calls, :help_needed_description, :text
  end
end
