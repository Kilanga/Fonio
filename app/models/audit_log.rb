class AuditLog < ApplicationRecord
  belongs_to :intervention, optional: true
  belongs_to :technician, optional: true

  validates :actor, presence: true
  validates :event_type, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
