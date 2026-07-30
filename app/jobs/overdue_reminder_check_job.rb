# Recurring job (see config/schedule.rb) — checks for interventions past their
# expected end time where the technician hasn't tapped "I'm done" in the
# portal yet, and flags one reminder (shown in-app on their next visit —
# no SMS since we dropped Twilio), never after 7pm local time (see SPEC.md
# section 8 and 9).
class OverdueReminderCheckJob < ApplicationJob
  queue_as :default

  CUTOFF_HOUR = 19

  def perform
    return if Time.current.hour >= CUTOFF_HOUR

    Intervention.overdue_for_reminder.find_each do |intervention|
      intervention.update!(reminder_sent_at: Time.current)

      AuditLog.create!(
        intervention: intervention, technician: intervention.technician,
        actor: "system", event_type: "reminder_sent"
      )
    end
  end
end
