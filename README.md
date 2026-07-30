# Fonio — CALL-E Field Intervention Tracker

A PM-facing web app that uses [CALL-E](https://www.heycall-e.com/) to check in on
field technicians 30 minutes into an intervention, and to collect a spoken
closing report once they signal they're done. See `SPEC.md` for the full
product spec (data model, decision trees, state machine, edge cases).

Built for the CALL-E "Your Code Is Calling" hackathon.

## Stack

- Ruby 3.2 / Rails 7.1, PostgreSQL, Tailwind, Hotwire (Turbo Streams for live updates)
- Solid Queue (DB-backed ActiveJob queue — no Redis needed)
- CALL-E API (outbound calls) + Twilio (SMS)

## Local setup

```bash
bundle install
rails db:create db:migrate db:seed
```

Create a `.env` file (not committed) with:

```
PM_AUTH_USER=pm
PM_AUTH_PASSWORD=<pick something that isn't "changeme">

CALLE_API_KEY=your_call_e_api_key
CALLE_BASE_URL=https://api.heycall-e.com
CALLE_WEBHOOK_URL=https://<your-public-url>/webhooks/call_e
# CALLE_WEBHOOK_SECRET=  # set once CALL-E issues one (see webhooks/call_e_controller.rb)
TWILIO_ACCOUNT_SID=your_twilio_sid
TWILIO_AUTH_TOKEN=your_twilio_token
TWILIO_FROM_NUMBER=+1...
APP_HOST=<your-public-url, no scheme>
```

`PM_AUTH_USER`/`PM_AUTH_PASSWORD` gate the entire PM interface (interventions,
technicians, dashboard, audit log, profile) behind HTTP Basic Auth — the app
logs a warning on boot if you leave the default password in place. The
technician-facing account area (`/technician/...`) and the CALL-E/Twilio
webhooks are unaffected (they have their own auth).

CALL-E's webhook and Twilio's inbound SMS webhook both need a **public URL**
reachable from the internet — for local development, expose your app with
`ngrok http 3000` (or similar) and use that URL for `CALLE_WEBHOOK_URL` and
your Twilio number's configured webhook.

Run **both** processes — the web server alone is not enough, since check-in
calls, retries, and report auto-validation all run as background jobs:

```bash
bin/dev          # web server + Tailwind watcher
bin/jobs          # Solid Queue worker — required for any job to actually run
```

Visit `http://localhost:3000`.

## Demo flow

1. Go to **Technicians**, add one, then confirm consent (required before any
   call/text can be sent to them — see SPEC.md section 9/11).
2. Go to **Pending**, schedule an intervention for that technician, click
   **Start**. A check-in call is scheduled 30 minutes out.
3. To test faster locally, you can trigger a call immediately from the Rails
   console: `CheckInCallJob.perform_now(Intervention.last)`.
4. Text `DONE` from the technician's phone to your Twilio number to trigger
   the closing report call.
5. Check **Tracking**, **Dashboard**, and **Audit Log** to see the results.

## Deployment (Heroku)

```bash
heroku create
heroku addons:create heroku-postgresql
heroku config:set PM_AUTH_USER=... PM_AUTH_PASSWORD=... \
  CALLE_API_KEY=... CALLE_BASE_URL=... CALLE_WEBHOOK_URL=... CALLE_WEBHOOK_SECRET=... \
  TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_FROM_NUMBER=... \
  APP_HOST=your-app.herokuapp.com
git push heroku main
heroku run rails db:migrate
heroku ps:scale web=1 worker=1
```

After deploying, visit `/pm_profile/new` once to set up your PM profile
(name, phone, region, language) — this is what the twice-daily summary
calls (noon and 6pm) use, and it replaces the old `PM_PHONE_NUMBER`/
`PM_REGION`/`PM_LOCALE` env vars.

The `worker` dyno (running `bin/jobs`, see `Procfile`) is required — without
it, check-in calls, retries, reminders, the daily summary call, and report
auto-validation will never fire. Recurring jobs (overdue reminder check,
daily summary call) are scheduled via Solid Queue's built-in recurring tasks
(`config/recurring.yml`), so no separate Heroku Scheduler add-on is needed.

Per the hackathon rules, this deployment must stay accessible through the
end of the judging period (October 13, 2026).

## SMS/voice opt-in & consent

Technicians never self-serve sign up for SMS/calls. The flow is:

1. The PM adds a technician (name + phone) from the web app.
2. Fonio immediately sends a one-time SMS with a secure activation link
   (e.g. *"Hi Marc, set up your Fonio account here: https://.../activate/abc123"*).
3. The technician opens the link and sets a password to activate their
   account. **Completing this activation step is the technician's own,
   self-asserted consent** to receive operational SMS and AI-initiated phone
   calls from Fonio related to their assigned field interventions —
   `Technician#consent_given` is only set once this step is completed, not
   by the PM on their behalf. See `SPEC.md`, sections 9 and 11.

No phone number is called or texted before this consent step is complete.
Recipients (technicians and the PM) can reply **STOP** at any time to stop
receiving messages, or **HELP** for support.

Examples of the outbound SMS Fonio sends, all tied to a specific
intervention or account action (never marketing):

- Account activation link (see above)
- One-time login code: *"Your Fonio login code: 483920 (valid 10 minutes)"*
- Post check-in-call confirmation, only sent if an issue was flagged:
  *"Fonio noted from your check-in call: issue: broken pump, severity: high.
  If that's wrong, please call your PM directly to correct it."*
- Closing report review link: *"Here's your closing report to review or
  edit: https://.../reports/xyz/edit"*
- Overdue check-in reminder: *"Hi Marc, just checking in on the intervention
  at Site A — text DONE once you've finished, or call us if you need more
  time."*
- PM-relayed instruction: *"Message from your PM: bring extra filters
  tomorrow"*

## Important notes

- **Consent**: technicians must be explicitly marked as consenting before
  any call or text is sent to them. Only use real phone numbers with actual
  consent — see SPEC.md section 9/11.
- **CALL-E API contract**: `app/services/call_e_client.rb` and
  `app/controllers/webhooks/call_e_controller.rb` reflect our best
  understanding of CALL-E's request/webhook shape at build time. Verify
  against `docs.heycall-e.com` and adjust if the real contract differs —
  that's the only place changes should be needed.
