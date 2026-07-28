class Intervention < ApplicationRecord
  belongs_to :technician
  has_many :calls, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  enum status: {
    pending: 0,
    in_progress: 1,
    no_show: 2,
    closing_in_progress: 3,
    action_required: 4,
    completed: 5,
    call_failed: 6,
    cancelled: 7
  }

  validates :site_name, presence: true
  validates :scheduled_at, presence: true

  scope :overdue_for_reminder, -> {
    in_progress.where(reminder_sent_at: nil).where.not(expected_end_time: nil)
      .where("expected_end_time < ?", Time.current)
  }

  def start!
    update!(status: "in_progress", started_at: Time.current)
    AuditLog.create!(intervention: self, technician: technician, actor: "pm", event_type: "intervention_started")
    CheckInCallJob.set(wait: 30.minutes).perform_later(self)
  end

  # Every scheduled call action (CheckInCallJob, ClosingReportCallJob) checks
  # the intervention's current status before placing any call, so cancelling
  # here reliably prevents an already-enqueued job from actually calling —
  # even though CALL-E's own Phase 1 beta API doesn't yet expose a
  # provider-side "cancel call" endpoint. See CALL-E community safety
  # guidance: every setup must have a clear cancellation path.
  def cancel!
    update!(status: "cancelled")
    AuditLog.create!(intervention: self, technician: technician, actor: "pm", event_type: "intervention_cancelled")
  end

  def resolution_time_minutes
    return nil unless completed_at && started_at
    ((completed_at - started_at) / 60).round
  end
end
