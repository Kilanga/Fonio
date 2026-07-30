# Sets up ready-to-use demo accounts for hackathon judges: 5 pre-activated
# technician accounts and a PM profile, all with placeholder phone numbers.
#
# Why pre-activated: normally a technician must open their own activation
# link and set a password themselves — that step *is* their consent (see
# SPEC.md section 3bis). For judge demo accounts we already have Arnaud's
# consent to stand these up, so we call `activate!` directly instead of
# requiring a real click-through, exactly like the single demo technician
# in db/seeds.rb already does.
#
# A judge then logs in with the phone/password printed below, and on the
# "confirm your details" screen shown right after login (already existing —
# TechnicianPortal::ConfirmationsController) types in *their own* real phone
# number, region, and language before starting a test intervention. The PM
# side works the same way via /pm_profile/edit.
#
# Usage:
#   rails demo:judges            # local
#   heroku run rails demo:judges # production
namespace :demo do
  task judges: :environment do
    password = "CallE2026Demo!"

    technicians = (1..5).map do |n|
      technician = Technician.find_or_initialize_by(phone: format("+1555000%04d", 2000 + n))
      technician.name = "Judge Tech #{n}"
      technician.save!(validate: false) unless technician.persisted?

      unless technician.activated?
        technician.start_activation!
        technician.activate!(password: password, password_confirmation: password)
      end
      technician.update!(region: "US", locale: "en-US") if technician.region.blank?
      technician
    end

    pm = Pm.first_or_create!(name: "Judge PM", phone: "+15550009000", region: "US", locale: "en-US")

    puts "\n== Judge demo accounts ready =="
    puts "Shared technician password: #{password}\n\n"
    technicians.each { |t| puts "  #{t.name}: phone=#{t.phone}" }
    puts "\nPM: phone=#{pm.phone} (edit at /pm_profile/edit, behind PM_AUTH_USER/PM_AUTH_PASSWORD)"
    puts "\nA judge logs in at /technician/login with one of the phone numbers above and the"
    puts "shared password, then enters their own real phone number on the confirmation screen"
    puts "shown right after login — that's what CALL-E will actually call."
  end
end
