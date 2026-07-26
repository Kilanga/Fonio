# Builds the structured "goal" prompt sent to CALL-E for each call type.
# These encode the decision trees defined in SPEC.md section 6, plus the
# language-handling instruction from section 6bis (conversation adapts to
# the technician's language; structured result always comes back in English).
module CallScripts
  LANGUAGE_INSTRUCTION = <<~TEXT.freeze
    Conduct the conversation in whatever language the technician speaks —
    detect it and adapt naturally. Regardless of the conversation language,
    always return the structured result entirely in English.
  TEXT

  RESULT_SCHEMA_NOTE = <<~TEXT.freeze
    If the person doesn't answer, note the call as unanswered rather than
    guessing at values. Be concise and outcome-focused, per CALL-E best
    practice: state who you are, the goal of the call, and what to do if
    the person can't talk right now.
  TEXT

  def self.check_in(intervention)
    <<~GOAL
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

      Return a structured result with: has_started (bool), has_issue (bool),
      issue_type (string, if any), severity (low/medium/blocking, if any),
      needs_help (bool), help_needed_description (string, if any),
      revised_eta (datetime, if any).

      #{LANGUAGE_INSTRUCTION}
      #{RESULT_SCHEMA_NOTE}
    GOAL
  end

  def self.closing_report(intervention)
    <<~GOAL
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

      Return a structured result with: work_completed (string),
      equipment_used (string), has_anomaly (bool), anomalies (string, if any),
      is_anomaly_severe (bool, if any), recommendations (string, if any),
      actual_duration_minutes (integer).

      #{LANGUAGE_INSTRUCTION}
      #{RESULT_SCHEMA_NOTE}
    GOAL
  end

  def self.daily_summary(date, interventions)
    completed = interventions.select { |i| i.status == "completed" }
    flagged   = interventions.select { |i| %w[action_required no_show call_failed].include?(i.status) }

    flagged_lines = flagged.map do |i|
      "- #{i.site_name} (#{i.technician.name}): #{i.status.humanize}"
    end.join("\n")

    <<~GOAL
      Call the project manager with an evening summary for #{date.strftime('%B %-d')}.

      Report:
      - #{completed.count} intervention(s) completed without issue.
      - #{flagged.count} intervention(s) need attention:
      #{flagged_lines.presence || '  (none)'}

      For each flagged item, state the site, technician, and reason in one
      sentence. Close by telling them full details are in their dashboard.

      This call is to the PM, not a technician, so it should be conducted in
      English throughout.
    GOAL
  end
end
