# Recurring job (see config/schedule.rb) — checks for interventions past their
# expected end time with no "DONE" SMS yet, and sends one reminder text,
# never after 7pm local time (see SPEC.md section 8 and 9).
class OverdueReminderCheckJob < ApplicationJob
  queue_as :default

  CUTOFF_HOUR = 19

  def perform
    return if Time.current.hour >= CUTOFF_HOUR

    Intervention.overdue_for_reminder.find_each do |intervention|
      SmsClient.send_sms(
        to: intervention.technician.phone,
        body: "Hi #{intervention.technician.name}, just checking in on the intervention " \
              "at #{intervention.site_name} — text DONE once you've finished, or call us " \
              "if you need more time."
      )
      intervention.update!(reminder_sent_at: Time.current)

      AuditLog.create!(
        intervention: intervention, technician: intervention.technician,
        actor: "system", event_type: "reminder_sent"
      )
    end
  end
end
