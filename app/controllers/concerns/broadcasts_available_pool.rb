# Shared by InterventionsController (PM creates an unassigned intervention)
# and TechnicianPortal::InterventionsController (a technician claims one) —
# both change what's in the shared pool, so both need to push a fresh
# render of it to every technician's index page.
module BroadcastsAvailablePool
  extend ActiveSupport::Concern

  private

  def broadcast_available_pool
    Turbo::StreamsChannel.broadcast_replace_to(
      "technician_pool",
      target: "technician_available_pool",
      partial: "technician_portal/interventions/available_pool",
      locals: { available: Intervention.available_to_claim.order(:scheduled_at) }
    )
  end
end
