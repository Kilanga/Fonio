# Thin wrapper around the CALL-E API (Phase 1 beta), matching the contract
# documented at https://github.com/CALLE-AI/call-e-integrations:
#
#   POST /v1/calls                — create a call
#   GET  /v1/calls/{call_id}      — read call state/results (poll fallback)
#   GET  /v1/calls/{call_id}/events — list call events
#
# Isolated here so the rest of the app never depends directly on CALL-E's
# request/response shape. Re-verify against docs.heycall-e.com before
# production use — Phase 1 beta contract may still evolve.
class CallEClient
  include HTTParty
  base_uri ENV.fetch("CALLE_BASE_URL", "https://api.heycall-e.com")

  class CallEError < StandardError; end
  class RateLimitError < CallEError; end

  # task: string — the natural-language goal for the call
  # recipient: { phone:, region:, locale: } — see CallESupportedRegions
  # result_schema: JSON Schema hash describing the expected structured result
  # metadata: arbitrary hash echoed back in webhooks/events
  # idempotency_key: string — prevents duplicate calls on retry
  def self.create_call(task:, recipient:, result_schema:, metadata: {}, idempotency_key:)
    response = post(
      "/v1/calls",
      headers: default_headers.merge("Idempotency-Key" => idempotency_key),
      body: {
        task: task,
        recipient: recipient,
        result_schema: result_schema,
        metadata: metadata,
        webhook_url: ENV.fetch("CALLE_WEBHOOK_URL")
      }.to_json
    )

    raise_for_response(response, "create_call")
    response.parsed_response
  rescue KeyError => e
    raise CallEError, "CALL-E not configured: #{e.message}"
  end

  def self.get_call(call_id)
    response = get("/v1/calls/#{call_id}", headers: default_headers)
    raise_for_response(response, "get_call")
    response.parsed_response
  rescue KeyError => e
    raise CallEError, "CALL-E not configured: #{e.message}"
  end

  def self.get_call_events(call_id)
    response = get("/v1/calls/#{call_id}/events", headers: default_headers)
    raise_for_response(response, "get_call_events")
    response.parsed_response
  rescue KeyError => e
    raise CallEError, "CALL-E not configured: #{e.message}"
  end

  # CALL-E documents built-in rate limits and concurrency controls as part
  # of its safety/governance features — surfaced here as a distinct error
  # so callers (or a future retry-with-backoff wrapper) can special-case it
  # rather than treating it like any other failure.
  def self.raise_for_response(response, action)
    return if response.success?

    if response.code == 429
      raise RateLimitError, "CALL-E #{action} rate-limited: #{response.body}"
    end

    raise CallEError, "CALL-E #{action} failed: #{response.code} #{response.body}"
  end
  private_class_method :raise_for_response

  def self.default_headers
    {
      "Authorization" => "Bearer #{ENV.fetch('CALLE_API_KEY')}",
      "Content-Type" => "application/json"
    }
  end
  private_class_method :default_headers
end
