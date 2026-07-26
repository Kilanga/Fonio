class DashboardController < ApplicationController
  def show
    @status_counts = Intervention.group(:status).count

    completed = Intervention.completed.where.not(started_at: nil, completed_at: nil)
    @avg_resolution_minutes = completed.average(
      Arel.sql("EXTRACT(EPOCH FROM (completed_at - started_at)) / 60")
    )&.round

    closing_reports = Call.type_closing_report.report_validated
    @total_reports = closing_reports.count
    @severe_anomaly_count = closing_reports.where(is_anomaly_severe: true).count
    @anomaly_rate = @total_reports.zero? ? 0 : ((@severe_anomaly_count.to_f / @total_reports) * 100).round(1)
  end
end
