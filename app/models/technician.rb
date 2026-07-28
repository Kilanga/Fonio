class Technician < ApplicationRecord
  include CallERecipient
  has_secure_password validations: false # we validate presence ourselves, only after activation

  has_many :interventions, dependent: :restrict_with_error
  has_many :audit_logs, dependent: :nullify

  validates :name, presence: true
  validates :phone, presence: true, uniqueness: true

  # --- Account activation (sets consent — see SPEC.md section 3bis) ---

  def start_activation!
    update!(
      activation_token: SecureRandom.urlsafe_base64(24),
      activation_token_expires_at: 24.hours.from_now
    )
  end

  def activation_token_valid?
    activation_token.present? && activation_token_expires_at.present? && activation_token_expires_at > Time.current
  end

  # Setting a password for the first time IS the technician's own consent —
  # a stronger, self-asserted signal than a PM checkbox on their behalf.
  def activate!(password:, password_confirmation:)
    return false unless activation_token_valid?

    if password.blank? || password.length < 8
      errors.add(:password, "must be at least 8 characters")
      return false
    end
    if password != password_confirmation
      errors.add(:password_confirmation, "doesn't match password")
      return false
    end

    self.password = password
    self.password_confirmation = password_confirmation
    self.account_activated_at = Time.current
    self.consent_given = true
    self.consent_given_at = Time.current
    self.activation_token = nil
    self.activation_token_expires_at = nil

    if save
      AuditLog.create!(technician: self, actor: "technician", event_type: "account_activated_and_consent_given")
      true
    else
      false
    end
  end

  def activated?
    account_activated_at.present?
  end

  # --- Login-code fallback (password reset / passwordless login) ---

  def generate_login_code!
    code = format("%06d", SecureRandom.random_number(1_000_000))
    update!(login_code: BCrypt::Password.create(code), login_code_expires_at: 10.minutes.from_now)
    code # return the plaintext code once, to be sent via SMS — never stored in plaintext
  end

  def verify_login_code(code)
    return false if login_code.blank? || login_code_expires_at.blank? || login_code_expires_at < Time.current
    BCrypt::Password.new(login_code) == code
  end

  def consume_login_code!
    update!(login_code: nil, login_code_expires_at: nil)
  end

  # --- Existing helpers ---

  def active_intervention
    interventions.in_progress.order(started_at: :desc).first
  end
end
