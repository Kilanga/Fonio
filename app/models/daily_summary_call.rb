class DailySummaryCall < ApplicationRecord
  WINDOWS = {
    "morning"   => [0, 12],  # 00:00–12:00
    "afternoon" => [12, 18]  # 12:00–18:00
  }.freeze

  FLAGGED_STATUSES = %w[action_required no_show call_failed].freeze

  def window_range
    start_hour, end_hour = WINDOWS.fetch(period)
    (date.beginning_of_day + start_hour.hours)...(date.beginning_of_day + end_hour.hours)
  end

  # The interventions this specific call's script would have read out to
  # the PM — used to resolve the PM's spoken decisions back to a specific
  # record (see Webhooks::CallEController#apply_daily_summary_decisions).
  def flagged_interventions
    Intervention.where(started_at: window_range, status: FLAGGED_STATUSES).includes(:technician)
  end
end
