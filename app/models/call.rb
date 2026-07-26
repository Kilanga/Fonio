class Call < ApplicationRecord
  belongs_to :intervention
  has_many_attached :photos

  enum call_type: {
    check_in: "check_in",
    closing_report: "closing_report",
    daily_summary: "daily_summary"
  }, _prefix: :type

  enum call_status: {
    initiated: "initiated",
    in_progress: "in_progress",
    answered: "answered",
    no_answer: "no_answer"
  }, _prefix: :status

  enum report_status: {
    draft: "draft",
    validated: "validated"
  }, _prefix: :report

  before_create :generate_edit_token, if: -> { call_type == "closing_report" }

  def edit_token_valid?
    edit_token.present? && edit_token_expires_at.present? && edit_token_expires_at > Time.current
  end

  private

  def generate_edit_token
    self.edit_token = SecureRandom.urlsafe_base64(24)
    self.edit_token_expires_at = 2.hours.from_now
    self.report_status ||= "draft"
  end
end
