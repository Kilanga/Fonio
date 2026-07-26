# Thin wrapper around Twilio for the two SMS use cases in this app:
# the technician's "DONE" closing signal (inbound, handled by the webhook
# controller directly) and outbound texts we send (report-edit link,
# overdue reminder).
class SmsClient
  include HTTParty
  base_uri "https://api.twilio.com/2010-04-01"

  class SmsError < StandardError; end

  def self.send_sms(to:, body:)
    account_sid = ENV.fetch("TWILIO_ACCOUNT_SID")
    auth_token  = ENV.fetch("TWILIO_AUTH_TOKEN")
    from        = ENV.fetch("TWILIO_FROM_NUMBER")

    response = post(
      "/Accounts/#{account_sid}/Messages.json",
      basic_auth: { username: account_sid, password: auth_token },
      body: { To: to, From: from, Body: body }
    )

    raise SmsError, "Twilio send_sms failed: #{response.code} #{response.body}" unless response.success?

    response.parsed_response
  end
end
