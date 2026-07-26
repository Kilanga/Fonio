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
CALLE_API_KEY=your_call_e_api_key
CALLE_BASE_URL=https://api.heycall-e.com
CALLE_WEBHOOK_URL=https://<your-public-url>/webhooks/call_e
TWILIO_ACCOUNT_SID=your_twilio_sid
TWILIO_AUTH_TOKEN=your_twilio_token
TWILIO_FROM_NUMBER=+1...
PM_PHONE_NUMBER=+1...
PM_REGION=FR
PM_LOCALE=fr-FR
APP_HOST=<your-public-url, no scheme>
```

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
heroku config:set CALLE_API_KEY=... CALLE_BASE_URL=... CALLE_WEBHOOK_URL=... \
  TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_FROM_NUMBER=... \
  PM_PHONE_NUMBER=... APP_HOST=your-app.herokuapp.com
git push heroku main
heroku run rails db:migrate
heroku ps:scale web=1 worker=1
```

The `worker` dyno (running `bin/jobs`, see `Procfile`) is required — without
it, check-in calls, retries, reminders, the daily summary call, and report
auto-validation will never fire. Recurring jobs (overdue reminder check,
daily summary call) are scheduled via Solid Queue's built-in recurring tasks
(`config/recurring.yml`), so no separate Heroku Scheduler add-on is needed.

Per the hackathon rules, this deployment must stay accessible through the
end of the judging period (October 13, 2026).

## Important notes

- **Consent**: technicians must be explicitly marked as consenting before
  any call or text is sent to them. Only use real phone numbers with actual
  consent — see SPEC.md section 9/11.
- **CALL-E API contract**: `app/services/call_e_client.rb` and
  `app/controllers/webhooks/call_e_controller.rb` reflect our best
  understanding of CALL-E's request/webhook shape at build time. Verify
  against `docs.heycall-e.com` and adjust if the real contract differs —
  that's the only place changes should be needed.
