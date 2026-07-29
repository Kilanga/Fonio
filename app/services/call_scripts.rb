# Builds the "task" prompt and "result_schema" (JSON Schema) sent to CALL-E
# for each call type, per the real API contract:
# https://github.com/CALLE-AI/call-e-integrations
#
# CALL-E's conversation language is tied to the recipient's region/locale
# (see CallESupportedRegions) — there is no free-form "detect any language"
# instruction to give it. The task prompt below only needs to state the
# call's purpose in English; CALL-E handles localizing the conversation
# itself based on the recipient's locale.
module CallScripts
  def self.check_in(intervention)
    task = <<~TASK
      Call #{intervention.technician.name} to check in on their field
      intervention at #{intervention.site_name}.

      Steps:
      1. Greet them and confirm you're speaking with the right person and site.
      2. Ask whether they have arrived on site and started the intervention.
         If not, record has_started = false and end the call politely.
      3. If started, ask whether everything is going well.
         - If yes: record has_issue = false.
         - If no: ask what kind of issue (equipment / site access / technical /
           other), whether it's blocking or they can keep going (severity:
           low/medium/blocking), and whether they need help or backup. If they
           need help, ask what they need. If not, ask whether they still expect
           to finish on time and record a revised ETA if not.

      If the person doesn't answer, don't guess at any values.
    TASK

    { task: task, result_schema: check_in_result_schema }
  end

  def self.check_in_result_schema
    {
      type: "object",
      required: ["has_started", "has_issue"],
      properties: {
        has_started: { type: "boolean" },
        has_issue: { type: "boolean" },
        issue_type: { type: "string", enum: ["equipment", "site_access", "technical", "other", "none"] },
        severity: { type: "string", enum: ["low", "medium", "blocking", "none"] },
        needs_help: { type: "boolean" },
        help_needed_description: { type: "string" },
        revised_eta: { type: "string", format: "date-time" }
      },
      additionalProperties: false
    }
  end

  def self.closing_report(intervention)
    task = <<~TASK
      Call #{intervention.technician.name} to collect their closing report
      for the field intervention at #{intervention.site_name}, which they
      just signaled as finished.

      Steps:
      1. Greet them and confirm they're done at the site.
      2. Ask what work they completed today (open-ended).
      3. Ask what equipment they used (open-ended).
      4. Ask whether they noticed any anomalies on site. If yes, ask them to
         describe it, whether it's severe or minor, and what they'd recommend
         going forward.
      5. Ask how long the intervention actually took, in minutes.
      6. Close by telling them they'll receive a text to review, edit, or add
         photos to their report if needed.
    TASK

    { task: task, result_schema: closing_report_result_schema }
  end

  def self.closing_report_result_schema
    {
      type: "object",
      required: ["work_completed", "equipment_used", "has_anomaly"],
      properties: {
        work_completed: { type: "string" },
        equipment_used: { type: "string" },
        has_anomaly: { type: "boolean" },
        anomalies: { type: "string" },
        is_anomaly_severe: { type: "boolean" },
        recommendations: { type: "string" },
        actual_duration_minutes: { type: "integer" }
      },
      additionalProperties: false
    }
  end

  # period: "morning" (interventions from 00:00-12:00) or "afternoon"
  # (12:00-18:00) — see DailySummaryCallJob for the exact window computation.
  def self.daily_summary(period, interventions)
    completed = interventions.select { |i| i.status == "completed" }
    flagged   = interventions.select { |i| %w[action_required no_show call_failed].include?(i.status) }

    flagged_lines = flagged.map { |i| "- #{i.site_name} (#{i.technician.name}): #{i.status.humanize}" }.join("\n")
    window_label = period == "morning" ? "this morning" : "this afternoon"

    task = <<~TASK
      Call the project manager with a summary of field interventions #{window_label}.

      Report:
      - #{completed.count} intervention(s) completed without issue #{window_label}.
      - #{flagged.count} intervention(s) need attention:
      #{flagged_lines.presence || '  (none)'}

      #{flagged.any? ? <<~FOLLOWUP.strip : "Close by telling them full details are in their dashboard."}
        For each flagged item, state the site, technician, and reason in one
        sentence, then ask whether they want to do anything about it right
        now:
        - Mark it resolved, if they say it's already been handled.
        - Send the technician a short text message on their behalf — if
          so, ask exactly what they want said, and keep it brief.
        - Or nothing for now — they'll handle it later from the dashboard.

        Record one entry in `decisions` for each flagged site the PM
        actually responds about, using the exact site name as stated
        above. If they don't mention a flagged site at all, leave it out
        of `decisions` entirely — never guess "no action" for something
        they didn't address. Close by telling them full details are in
        their dashboard either way.
      FOLLOWUP
    TASK

    { task: task, result_schema: daily_summary_result_schema }
  end

  def self.daily_summary_result_schema
    {
      type: "object",
      required: ["acknowledged"],
      properties: {
        acknowledged: { type: "boolean" },
        decisions: {
          type: "array",
          items: {
            type: "object",
            required: ["site_name", "action"],
            properties: {
              site_name: { type: "string" },
              action: { type: "string", enum: ["mark_resolved", "text_technician", "no_action"] },
              instruction: { type: "string" }
            },
            additionalProperties: false
          }
        }
      },
      additionalProperties: false
    }
  end
end
