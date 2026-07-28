module ApplicationHelper
  # Masks a phone number for display in user-facing summaries, per CALL-E's
  # community safety guidance ("Mask phone numbers in user-facing
  # summaries"). Keeps enough to recognize/verify a number without fully
  # exposing it (e.g. "+33 6•• •• •• 78").
  def masked_phone(phone)
    return "" if phone.blank?
    digits = phone.to_s
    return digits if digits.length <= 5

    "#{digits[0..3]}#{'•' * (digits.length - 6)}#{digits[-2..]}"
  end
end
