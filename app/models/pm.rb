# Single-PM MVP: this table is expected to hold exactly one row. Created
# once via the PM settings page (name, phone, region, locale) — no
# reconfirmation needed at each visit, unlike Technician, since the PM is
# the person operating the app directly rather than someone CALL-E infers
# details about.
class Pm < ApplicationRecord
  include CallERecipient

  validates :name, presence: true
  validates :phone, presence: true
  validates :region, presence: true
  validates :locale, presence: true
end
