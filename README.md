# Fonio — CALL-E Field Intervention Tracker

A PM-facing web app that uses [CALL-E](https://www.heycall-e.com/) to check in on
field technicians 30 minutes into an intervention, and to collect a spoken
closing report once they signal they're done. See `SPEC.md` for the full
product spec (data model, decision trees, state machine, edge cases).

Built for the CALL-E "Your Code Is Calling" hackathon.

## Stack

- Ruby 3.2 / Rails 7.1, PostgreSQL, Tailwind, Hotwire (Turbo Streams for live updates)
- Solid Queue (DB-backed ActiveJob queue — no Redis needed)
- CALL-E API (outbound AI voice calls) — the only external service this app
  depends on. There is no SMS/Twilio dependency: everything technician-facing
  that isn't a phone call happens in their own mobile-first web portal
  (`/technician/...`).

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
APP_HOST=<your-public-url, no scheme>
```

`PM_AUTH_USER`/`PM_AUTH_PASSWORD` gate the entire PM interface (interventions,
technicians, dashboard, audit log, profile) behind HTTP Basic Auth — the app
logs a warning on boot if you leave the default password in place. The
technician-facing account area (`/technician/...`) and the CALL-E webhook are
unaffected (they have their own auth).

CALL-E's webhook needs a **public URL** reachable from the internet — for
local development, expose your app with `ngrok http 3000` (or similar) and
use that URL for `CALLE_WEBHOOK_URL`.

Run **both** processes — the web server alone is not enough, since check-in
calls, retries, and report auto-validation all run as background jobs:

```bash
bin/dev          # web server + Tailwind watcher
bin/jobs          # Solid Queue worker — required for any job to actually run
```

Visit `http://localhost:3000`.

## Demo flow

1. Go to **Technicians**, add one. Fonio generates an activation link (shown
   right there in the UI) — share it with the technician any way you like
   (WhatsApp, email, in person). Opening it and setting a password *is*
   their consent to receive AI-initiated calls — see SPEC.md section 9/11.
2. The technician logs into their portal at `/technician/login` (phone +
   password) and accepts/starts the intervention themselves — or, from the
   PM side, go to **Pending**, schedule an intervention for that technician,
   and click **Start**. A check-in call is scheduled 30 minutes out.
3. To test faster locally, you can trigger a call immediately from the Rails
   console: `CheckInCallJob.perform_now(Intervention.last)`.
4. The technician taps **"I'm done"** in their portal (intervention show
   page) to trigger the closing report call — this replaces what used to be
   a "text DONE" SMS flow.
5. Check **Tracking**, **Dashboard**, and **Audit Log** to see the results.

## Deployment (Heroku)

```bash
heroku create
heroku addons:create heroku-postgresql
heroku config:set PM_AUTH_USER=... PM_AUTH_PASSWORD=... \
  CALLE_API_KEY=... CALLE_BASE_URL=... CALLE_WEBHOOK_URL=... CALLE_WEBHOOK_SECRET=... \
  APP_HOST=your-app.herokuapp.com
git push heroku main
heroku run rails db:migrate
heroku ps:scale web=1 worker=1
```

After deploying, visit `/pm_profile/new` once to set up your PM profile
(name, phone, region, language) — this is what the twice-daily summary
calls (noon and 6pm) use.

The `worker` dyno (running `bin/jobs`, see `Procfile`) is required — without
it, check-in calls, retries, reminders, the daily summary call, and report
auto-validation will never fire. Recurring jobs (overdue reminder check,
daily summary call) are scheduled via Solid Queue's built-in recurring tasks
(`config/recurring.yml`), so no separate Heroku Scheduler add-on is needed.

Per the hackathon rules, this deployment must stay accessible through the
end of the judging period (October 13, 2026).

## Voice call opt-in & consent

Technicians never self-serve sign up for AI-initiated calls. The flow is:

1. The PM adds a technician (name + phone) from the web app.
2. Fonio generates a one-time account activation link, shown directly in the
   PM's technician list. The PM shares it with the technician however they
   want — there's no automated channel for this step.
3. The technician opens the link and sets a password to activate their
   portal account. **Completing this activation step is the technician's
   own, self-asserted consent** to receive AI-initiated phone calls from
   Fonio related to their assigned field interventions —
   `Technician#consent_given` is only set once this step is completed, not
   by the PM on their behalf. See `SPEC.md`, sections 9 and 11.

No phone number is ever called before this consent step is complete.

Everything else — check-in call results, the closing-report review link,
messages relayed from the PM, and overdue reminders — is surfaced to the
technician inside their portal (`technician_portal/interventions#show`) the
next time they open the app, instead of being pushed by SMS.

## Important notes

- **Consent**: technicians must be explicitly marked as consenting before
  any call is placed to them. Only use real phone numbers with actual
  consent — see SPEC.md section 9/11.
- **No SMS/Twilio dependency**: an earlier version of this app used Twilio
  for SMS (activation links, login codes, notifications, the "text DONE"
  signal). It was dropped — US carrier compliance (A2P 10DLC / toll-free
  verification) requires either a US/Canada address or a registered
  business, neither of which this hackathon project has. Every one of those
  touchpoints now has an in-app equivalent in the technician portal instead.
- **CALL-E API contract**: `app/services/call_e_client.rb` and
  `app/controllers/webhooks/call_e_controller.rb` reflect our best
  understanding of CALL-E's request/webhook shape at build time. Verify
  against `docs.heycall-e.com` and adjust if the real contract differs —
  that's the only place changes should be needed.
