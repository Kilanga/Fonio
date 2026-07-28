# Demo seed data — a fully activated test technician (password: "password123")
# and a couple of interventions, useful for local testing and for judges
# exploring the deployed app.
# IMPORTANT: replace the phone number below with a real, consenting test
# number before placing any actual CALL-E call (see SPEC.md section 9/11).

technician = Technician.find_or_initialize_by(phone: "+15550001111")
technician.name = "Alex Demo"
technician.save!(validate: false) unless technician.persisted?

unless technician.activated?
  technician.start_activation!
  technician.activate!(password: "password123", password_confirmation: "password123")
  technician.update!(region: "US", locale: "en-US")
end

Pm.first_or_create!(name: "Sam PM", phone: "+15550009999", region: "US", locale: "en-US")

Intervention.find_or_create_by!(site_name: "Downtown Relay Cabinet") do |i|
  i.technician = technician
  i.site_address = "12 Main St"
  i.scheduled_at = 1.hour.from_now
  i.expected_end_time = 3.hours.from_now
end

Intervention.find_or_create_by!(site_name: "North Substation") do |i|
  i.technician = technician
  i.site_address = "88 Industrial Ave"
  i.scheduled_at = 30.minutes.ago
  i.started_at = 20.minutes.ago
  i.status = "in_progress"
  i.accepted_at = 40.minutes.ago
  i.expected_end_time = 1.hour.from_now
end

puts "Seeded #{Technician.count} technician(s) and #{Intervention.count} intervention(s)."
puts "Demo technician login: phone=#{technician.phone} password=password123"
