class ApplicationController < ActionController::Base
  protected

  # Simple fixed-window rate limiter backed by Rails.cache. Not atomic and
  # not distributed-safe, but enough to blunt brute-force/spam attempts for
  # this MVP's traffic level. NOTE: in development, Rails.cache is a
  # NullStore by default (caching disabled) so this fails open — enable it
  # with `bin/rails dev:cache` to actually exercise rate limiting locally.
  def rate_limited?(key, limit:, period:)
    count = Rails.cache.read(key) || 0
    return true if count >= limit

    Rails.cache.write(key, count + 1, expires_in: period)
    false
  end
end
