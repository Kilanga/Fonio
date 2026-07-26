class Technician < ApplicationRecord
  has_many :interventions, dependent: :restrict_with_error
  has_many :audit_logs, dependent: :nullify

  validates :name, presence: true
  validates :phone, presence: true, uniqueness: true

  def give_consent!
    update!(consent_given: true, consent_given_at: Time.current)
    AuditLog.create!(technician: self, actor: "pm", event_type: "consent_given", details: { phone: phone })
  end

  def active_intervention
    interventions.in_progress.order(started_at: :desc).first
  end
end
