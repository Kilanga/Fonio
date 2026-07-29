# Lets the PM read the raw CALL-E transcript/events behind a structured
# result, so they can double-check what was actually said when a
# structured field (severity, anomaly, etc.) looks off. Fetched live from
# CALL-E rather than stored, since CallEClient.get_call_events already
# exists for exactly this (poll-fallback) purpose — see SPEC.md's note on
# verifying CALL-E's real contract once tested live.
class CallsController < ApplicationController
  include PmAuthenticatable

  before_action :find_call

  def transcript
    if @call.call_e_call_id.blank?
      @error = "This call hasn't reached CALL-E yet (no call_e_call_id) — nothing to fetch."
      return
    end

    @events = CallEClient.get_call_events(@call.call_e_call_id)
  rescue CallEClient::CallEError => e
    @error = "Couldn't fetch the transcript from CALL-E: #{e.message}"
  end

  private

  def find_call
    # Scoped through the intervention so a call from another intervention
    # can't be requested by guessing its id.
    @intervention = Intervention.find(params[:intervention_id])
    @call = @intervention.calls.find(params[:id])
  end
end
