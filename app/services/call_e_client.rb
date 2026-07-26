# Thin wrapper around the CALL-E API, isolated so the rest of the app never
# depends directly on CALL-E's exact request/response shape. If the real
# contract differs from what we assumed while building this (sync vs async,
# field names, etc.), only this file should need to change.
#
# NOTE: verify base URL, auth scheme, and exact endpoint/payload shape against
# https://docs.heycall-e.com/ before going live — this reflects our best
# understanding at build time.
class CallEClient
  include HTTParty
  base_uri ENV.fetch("CALL_E_API_BASE_URL", "https://api.heycall-e.com")

  class CallEError < StandardError; end

  def self.create_call(to:, goal:, metadata: {})
    response = post(
      "/v1/calls",
      headers: default_headers,
      body: {
        to: to,
        goal: goal,
        metadata: metadata,
        webhook_url: ENV.fetch("CALL_E_WEBHOOK_URL")
      }.to_json
    )

    raise CallEError, "CALL-E create_call failed: #{response.code} #{response.body}" unless response.success?

    response.parsed_response
  end

  def self.default_headers
    {
      "Authorization" => "Bearer #{ENV.fetch('CALL_E_API_KEY')}",
      "Content-Type" => "application/json"
    }
  end
  private_class_method :default_headers
end
