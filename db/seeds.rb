# Demo seed data — a consented test technician and a couple of interventions,
# useful for local testing and for judges exploring the deployed app.
# IMPORTANT: replace the phone number below with a real, consenting test
# number before placing any actual CALL-E call (see SPEC.md section 9/11).

technician = Technician.find_or_create_by!(phone: "+15550001111") do |t|
  t.name = "Alex Demo"
end
technician.give_consent! unless technician.consent_given?

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
  i.expected_end_time = 1.hour.from_now
end

puts "Seeded #{Technician.count} technician(s) and #{Intervention.count} intervention(s)."
