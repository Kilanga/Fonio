class AuditLogsController < ApplicationController
  def index
    @audit_logs = AuditLog.includes(:intervention, :technician).recent_first.limit(200)
  end
end
