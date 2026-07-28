# Fonio — CALL-E Field Intervention Tracker

## 1. Problem

In field maintenance operations (telecom infrastructure, or any business with dispersed
technicians/subcontractors), a project manager today has to:
- Manually call or message each technician to check whether an intervention is going well
- Wait for a closing report that's often late, incomplete, or never written at all
- Discover a blocker or anomaly long after it could have been addressed
- Manually compile a daily status overview across every open intervention

This manual follow-up cost is real and constant: across a portfolio of dozens of
interventions per month, every phone check-in or email reminder is PM time lost, and every
late-reported anomaly can mean an SLA penalty or a delayed job.

## 2. Solution

A PM-facing web app that uses CALL-E to:
1. **Automatically call the technician 30 minutes after an intervention starts**, to confirm
   they've actually started, that there's no blocker, and to capture any need for help.
2. **Call the technician to collect a spoken closing report**, triggered by a "DONE" SMS sent
   by the technician to a dedicated number — removing the chore of manually typing up a
   report. The technician can still review/edit the transcribed report afterward via a secure
   link (Kizeo-style), including attaching photos.
3. **Call the PM every evening with a spoken daily summary** of all interventions handled
   that day — a status briefing without the PM having to open the dashboard.

The PM tracks everything from a web interface with live updates, search/filtering, a
synthesis dashboard, CSV export, and a full audit log of every call and status change.

## 3. Users

- **PM**: the only user of the web interface. Registers technicians (with explicit consent),
  starts interventions, reviews results, handles anomalies, receives the daily summary call.
  Single-PM assumption for this MVP (no multi-user auth).
- **Technician**: never uses the web app. Interacts only by phone (receives CALL-E calls),
  by SMS ("DONE" to close out, reminder texts), and via a no-login secure link to edit their
  closing report.

## 4. Data model

```ruby
class Technician < ApplicationRecord
  # name:string, phone:string (unique)
  # consent_given:boolean, default: false
  # consent_given_at:datetime
  has_many :interventions
  has_many :audit_logs
end

class Intervention < ApplicationRecord
  belongs_to :technician
  # site_name:string, site_address:string
  # scheduled_at:datetime, started_at:datetime
  # expected_end_time:datetime          -- used for the overdue-reminder check
  # reminder_sent_at:datetime           -- ensures the reminder SMS fires only once
  # completed_at:datetime               -- used for resolution-time metrics
  enum status: {
    pending: 0,
    in_progress: 1,
    no_show: 2,               # technician confirmed they haven't started
    closing_in_progress: 3,
    action_required: 4,
    completed: 5,
    call_failed: 6            # check-in call unanswered after retry
  }
  has_many :calls, dependent: :destroy
  has_many :audit_logs
end

class Call < ApplicationRecord
  belongs_to :intervention
  # call_type:string     -> "check_in" | "closing_report"
  # call_status:string   -> initiated / in_progress / answered / no_answer
  # attempt:integer       -> 1 or 2 (check-in retry logic)
  # call_e_call_id:string
  # raw_payload:jsonb

  # check_in fields
  # has_started:boolean   -> false triggers Intervention#no_show
  # has_issue:boolean, severity:string, needs_help:boolean, revised_eta:datetime

  # closing_report fields
  # report_status:string  -> "draft" | "validated"
  # edit_token:string, edit_token_expires_at:datetime
  # work_completed:text, equipment_used:text, anomalies:text
  # recommendations:text, actual_duration_minutes:integer, is_anomaly_severe:boolean
  has_many_attached :photos   # ActiveStorage, added on the report-edit page
end

class DailySummaryCall < ApplicationRecord
  # date:date
  # pm_phone:string
  # call_e_call_id:string
  # call_status:string
  # raw_payload:jsonb
end

class AuditLog < ApplicationRecord
  belongs_to :intervention, optional: true
  belongs_to :technician, optional: true
  # actor:string       -> "pm" | "technician" | "system" | "call_e" | "twilio"
  # event_type:string  -> e.g. "call_initiated", "call_result_received",
  #                        "sms_received", "sms_ignored_duplicate", "status_changed",
  #                        "consent_given", "reminder_sent"
  # details:jsonb
  # created_at:datetime
end
```

## 5. Lifecycle (state machine)

```
pending
  → (PM clicks "Start") → in_progress
      → [check-in call, attempt 1]
          ├─ "haven't started yet" → no_show (PM follows up manually)
          ├─ answered, started, no issue → in_progress
          ├─ answered, started, issue/help needed → action_required
          └─ no_answer → retry at +5min
              ├─ answered → (same branches as above)
              └─ no_answer → call_failed
      → (overdue reminder, if expected_end_time passed and before 7pm, "DONE" not yet received)
          → one reminder SMS sent (reminder_sent_at set, never repeated)
      → ("DONE" SMS received) → closing_in_progress
          → [closing_report call] → report in "draft" state
              → (technician validates via secure link, or 2h timeout)
                  → completed | action_required (if is_anomaly_severe)
action_required → (PM resolves) → completed
call_failed → (PM handles manually) → completed | in_progress
no_show → (PM handles manually, e.g. reschedules) → in_progress | completed
```

Duplicate "DONE" SMS handling: the webhook only acts on a technician's *current* `in_progress`
intervention. A second "DONE" SMS finds no matching `in_progress` intervention (it has already
moved to `closing_in_progress`/beyond) and is logged as `sms_ignored_duplicate` in the audit
log rather than triggering a second closing call.

## 6. Call scripts (decision trees)

These become the structured `goal` prompt sent to CALL-E, paired with the expected
structured-result schema.

### Check-in call (T+30min)
```
1. Greeting + confirm identity/site
2. "Have you arrived on site and started the intervention?"
   ├─ No → close, status = no_show
   └─ Yes → continue
3. "Is everything going well?"
   ├─ Yes, nothing to report → close, no issue
   └─ No / issue
       ├─ "What kind of issue?" (equipment / site access / technical / other)
       ├─ "Is it blocking or can you keep going?" → severity (low/medium/blocking)
       ├─ "Do you need help or backup?"
       │   ├─ Yes → "What do you need?" → status = action_required
       │   └─ No → "Do you still expect to finish on time?" → revised ETA
       └─ Close
```

### Closing report call (triggered by "DONE" SMS)
```
1. Greeting + confirm "Are you done at [site]?"
2. "What work did you complete today?" (work_completed, open)
3. "What equipment did you use?" (equipment_used, open)
4. "Did you notice any anomalies on site?"
   ├─ No → go to step 5
   └─ Yes
       ├─ "Describe the anomaly" (anomalies)
       ├─ "Is it severe or minor?" → is_anomaly_severe (bool)
       └─ "What do you recommend going forward?" (recommendations)
5. "How long did it actually take?" (actual_duration_minutes)
6. Close: "You'll get a text to review/edit your report and add photos if needed."
```

### Daily summary call (to the PM, every evening)
```
1. Greeting
2. State how many interventions were: completed without issue, flagged action_required,
   no_show, or call_failed today
3. For each action_required / no_show / call_failed item: site name, technician name,
   one-line reason
4. Close: "Full details are in your dashboard."
```

## 6bis. Language handling (corrected against the real API contract)

**Correction from initial assumption**: CALL-E does not offer free-form
"detect and adapt to any language" behavior. The real API contract
(`POST /v1/calls`) ties conversation language to a fixed list of supported
recipient regions, each with one or two specific languages — see
`app/models/concerns/call_e_supported_regions.rb` for the full list (17
regions as of Phase 1 beta, e.g. `FR` -> French, `DE` -> English/German,
`IN` -> English/Hindi).

Practical implications:
- Each `Technician` must have a `region` and a `locale` valid for that
  region (enforced by model validation).
- A technician whose preferred spoken language isn't tied to their region
  code cannot be accommodated by CALL-E today — this is a real product
  limitation worth flagging to the CALL-E team as feedback (see the
  hackathon's "Most Valuable Feedback" prize), not something to route
  around in our own code.
- The `task` prompt sent to CALL-E doesn't need a "detect the language"
  instruction — the platform localizes the conversation automatically based
  on the recipient's region/locale.

## 7. Report editing (Kizeo-style)

After the closing call, the technician receives a text with a secure, tokenized link to
review and edit the transcribed report — no login required. The same page allows attaching
photos (ActiveStorage) taken on site.

```
GET   /reports/:token/edit
PATCH /reports/:token
```

If the technician doesn't act within 2 hours, the report auto-validates
(`ValidateReportAutomaticallyJob`), and the intervention moves to `completed` or
`action_required` depending on `is_anomaly_severe`.

## 7bis. CALL-E API contract (verified, Phase 1 beta)

Verified directly against https://github.com/CALLE-AI/call-e-integrations
(README, "API (Preview / In Development)" section):

```
POST /v1/calls
Authorization: Bearer $CALLE_API_KEY
Idempotency-Key: <unique per logical call attempt>
Content-Type: application/json

{
  "task": "<natural language goal>",
  "recipient": { "phone": "+...", "region": "FR", "locale": "fr-FR" },
  "result_schema": { <JSON Schema for the structured result> },
  "metadata": { ... },
  "webhook_url": "https://.../webhooks/call_e"
}
```

Also available: `GET /v1/calls/{call_id}` (read state/results — useful as a
polling fallback if a webhook is missed) and `GET /v1/calls/{call_id}/events`
(list call events). Batch calls, scheduled calls, cancel calls, and
project-level webhook management are explicitly out of scope for Phase 1 —
consistent with our own architecture, which handles all scheduling
(30-min wait, 5-min retry, 2h auto-validation) via our own ActiveJob/Solid
Queue timers rather than relying on CALL-E to schedule anything.

This corrects our earlier assumption of a `{ to, goal, metadata, webhook_url }`
body — the real fields are `task` (not `goal`), a structured `recipient`
object (not a flat phone string), and a required `result_schema`. See
`app/services/call_e_client.rb` and `app/services/call_scripts.rb`.

**Marketing feature list vs. actual API scope**: CALL-E's own "Other
Features" table (product vision, not API-specific) lists "Scheduled &
Batch Calling" as a capability. The API-specific section of the same page
explicitly states batch calls, scheduled calls, and cancel calls are "still
outside the current beta scope." This doesn't affect us — our architecture
never relies on CALL-E to schedule anything; all timing (30-min check-in
wait, 5-min retry, 2h report auto-validation, daily summary) is handled by
our own ActiveJob/Solid Queue jobs — but it's worth knowing the two
descriptions of the product aren't the same thing when reading their docs.

Also per their documented feature set: CALL-E's runtime handles voicemail,
hold, transfers, and interruptions ("Real-World Voice Runtime"), and has
its own rate limiting and concurrency controls ("Built-In Safety &
Governance"). We've added a `voicemail` call_status (treated like
`no_answer` for retry purposes) and a `CallEClient::RateLimitError` (429
responses trigger a short technical retry rather than counting against the
check-in retry budget) — both defensive, unconfirmed against a real
payload yet.

## 3bis. Technician accounts (redesign)

**Change of design**: technicians now have their own account and log into a
separate, mobile-first section of the app — they are no longer purely
phone/SMS-only as originally scoped. This gives a stronger, self-asserted
consent and lets the technician (not the PM) confirm their own phone number
and preferred language.

**Auth**: phone + password (`has_secure_password`). A one-time SMS code is
also available as a login fallback / password reset path — no separate
account recovery flow needed beyond that.

**Account activation (replaces PM-driven consent)**: when the PM adds a
technician (name + phone), the system sends an SMS with a secure activation
link. The technician sets their own password there. Completing activation
*is* their consent to receive AI-initiated calls/texts — a stronger, self
-asserted signal than a PM checkbox on their behalf. `Technician#consent_given`
is now set by this action, not by the PM.

**Confirm-at-login**: every time a technician logs in, before seeing
anything else, they're shown their phone number and current preferred
region/language and asked to confirm or change them. This directly
satisfies the community safety rule against inferring these details — the
technician states them explicitly, every session.

**Acceptance and start (new intervention sub-steps, same `pending` status)**:
- PM schedules an intervention (`status: pending`, assigned to a technician)
  as before, but no longer has a "Start" button — that action now belongs
  to the technician.
- Technician logs in, sees their assigned pending interventions, and can
  **Accept** one (`accepted_at` timestamp set). This does not yet start the
  clock.
- When actually on site, the technician clicks **"I've started"**
  (`Intervention#start!`, called from the technician's own session) — this
  is what moves the intervention to `in_progress` and schedules the
  check-in call 30 minutes out, exactly as before. The PM's Pending tab
  becomes read-only/informational (shows whether the technician has
  accepted yet), rather than an action button.

**Data model additions**:
```ruby
class Technician
  # password_digest:string  (has_secure_password)
  # account_activated_at:datetime
end

class Intervention
  # accepted_at:datetime
end
```

## 8. Triggers and integrations

| Event | Trigger | Mechanism |
|---|---|---|
| Technician onboarded | PM adds technician + confirms consent | `POST /technicians` (consent screen, mandatory checkbox) |
| Intervention starts | PM button (simulates field trigger) | `POST /interventions/:id/start` |
| Check-in call | Automatic, T+30min after start | `CheckInCallJob` |
| Check-in result | CALL-E → our server | Webhook `POST /webhooks/call_e` |
| Retry on no-answer | Automatic, +5min after failed attempt | `CheckInCallJob` re-enqueued, `attempt: 2` |
| Overdue reminder | Recurring check (every ~30min), expected_end_time passed, before 7pm | `OverdueReminderCheckJob` → SMS via Twilio |
| Intervention ends | Technician SMS to dedicated number | Webhook `POST /webhooks/sms_technician` (dedup-aware) |
| Closing report call | Automatic, on "DONE" SMS receipt | `ClosingReportCallJob` |
| Closing report result | CALL-E → our server | Webhook `POST /webhooks/call_e` (same endpoint, distinguished by `call_type`) |
| Report auto-validation | 2h after draft creation, if untouched | `ValidateReportAutomaticallyJob` |
| Daily summary call | Recurring, once daily (e.g. 6pm) | `DailySummaryCallJob` |
| Live UI update | On every relevant webhook | `Turbo::StreamsChannel.broadcast_replace_to` |
| Audit logging | On every event above | `AuditLog.create!` alongside each state change |

Recurring jobs (`OverdueReminderCheckJob`, `DailySummaryCallJob`) are scheduled via the
`whenever` gem (cron-style) or the Heroku Scheduler add-on.

## 9. Interface

**Tabs**
1. **Pending** — scheduled interventions + "Start" button
2. **In Progress** — cards with countdown to check-in call, live call status, "awaiting
   closing" badge once the SMS is received
3. **Tracking** — sortable/filterable by status, severity, technician, and site; search bar;
   each card expands to show full call history (not just the latest), the closing report,
   and attached photos

**Dashboard** (synthesis view)
- Count of interventions per status (today / this week / all-time)
- Average resolution time (completed_at − started_at)
- Anomaly rate (is_anomaly_severe / total closing reports)
- CSV export button (interventions + linked closing report fields)

**Technician management**
- List/add technicians, each with a mandatory consent screen before a phone number can be
  used to place calls or send texts: *"I confirm this technician has been informed and
  consents to receiving AI-initiated phone calls and texts."*

**Audit log view**
- Simple chronological table (event_type, actor, intervention, timestamp, details) for
  transparency and debugging — also useful during judge testing to show the full trace of
  what CALL-E actually did.

## 10. Edge cases (MVP)

- No answer on check-in call → 1 automatic retry 5 min later, then `call_failed`
- Technician confirms they haven't started → `no_show`, PM handles manually
- Duplicate "DONE" SMS → logged as ignored, no duplicate closing call triggered
- SMS from an unrecognized number → silently ignored (logged in audit log)
- Reminder SMS fires at most once per intervention, never after 7pm
- One technician = one `in_progress` intervention at a time (simplifying assumption,
  documented)
- No external notification (Slack/email) for escalation — visual only, in the Tracking tab
  and the daily summary call

## 11. Tech stack

- **Rails** (Hotwire/Turbo for live updates, no separate SPA)
- **PostgreSQL**
- **ActiveJob** (Solid Queue or Sidekiq) for scheduled/retry jobs
- **ActiveStorage** for photo attachments on closing reports
- **whenever** gem or Heroku Scheduler for recurring jobs (reminders, daily summary)
- **CALL-E** (API/SDK) for outbound calls — isolated in a `CallEClient` wrapper class
- **Twilio** (or equivalent) for the closing SMS and reminder SMS
- **Deployment**: Heroku or Render (Starter tier), auto-deploy from GitHub — must stay
  accessible through the end of the judging period (October 13, 2026)

## 12. MVP scope (all features below are now in scope, per project decision)

- 3 tracking tabs + dashboard + search/filter + CSV export
- Both technician-facing call types + the daily PM summary call, all actually executed via
  CALL-E at runtime
- Technician model with mandatory consent screen
- Full call history per intervention (not just latest)
- Duplicate SMS detection, no_show status, call_failed + retry
- Overdue reminder SMS (pre-7pm cutoff)
- Report editing via secure link, with photo upload
- Full audit log across all events
- Live updates via Turbo Streams
- Stable, accessible deployment

**Stretch (only if time remains after the above)**
- Support for multiple simultaneous interventions per technician
- Multi-PM / multi-team with authentication
- Configurable retry counts / thresholds

## 13. Hackathon rules compliance

**Submission target**: our project fits the "User-facing Apps" contribution
area of `CALLE-AI/awesome-phone-call-agents` (`apps/` folder), matching
their listed examples "customer callback app" / "business call workbench".

**Repo-wide safety rules** (from `awesome-phone-call-agents`, applicable to
any contribution including apps): reviewed in full and aligned —
- Region/locale are explicit PM choices, never inferred from the phone
  number's country code (an earlier auto-suggestion feature was removed
  for this reason).
- Phone numbers are masked in all user-facing views (technicians list,
  intervention detail/cards); only the actual SMS/call-sending code paths
  use the unmasked number.
- Every intervention has a clear cancellation path (`cancel!`) before any
  call is placed, satisfying their "every setup must include cancellation
  instructions" guidance — enforced on our side via job status checks,
  since CALL-E's Phase 1 beta API has no provider-side cancel-call endpoint.
- Consent is required before any call/text (`Technician#consent_given?`),
  consistent with their "do not create third-party recurring calls unless
  the user explicitly states recipient consent" rule.
- No hidden or duplicate recurring jobs — our two recurring tasks (overdue
  reminder check, daily summary) are declared openly in
  `config/recurring.yml`.

- CALL-E is **actually called at runtime** (no mocked responses) — a pass/fail condition of
  Stage 1 judging
- Project **built entirely during the Submission Period** (July 23 – September 14, 2026)
- Deployment designed to **stay accessible through October 13, 2026** (end of judging)
- CALL-E used only with a test number / explicit consent — never a real technician's number
  without authorization (enforced in-app via the consent screen)
- Demo video < 3 minutes, no copyrighted music or unauthorized third-party trademarks
- PR to be opened on `CALL-E-AI/awesome-phone-call-agents`, in the correct Contribution Area
- App interface fully in English so judges can test it without a language barrier
