module StripeBilling
  # The agency's Stripe account (one row), connected through the OAuth broker. Its access token
  # is the account's own API key for this platform, so Runwell calls Stripe with it directly,
  # and Stripe sends that account's events to this install's webhook endpoint.
  class Connection < ::ApplicationRecord
    self.table_name = "stripe_billing_connections"

    # The token acts on the agency's whole Stripe account; the webhook secret proves an event
    # came from Stripe; the verifier finishes a sign-in in flight.
    encrypts :access_token
    encrypts :webhook_secret
    encrypts :code_verifier

    CURRENCY = "usd"

    validate :ensure_singleton, on: :create

    def self.current = first
    def self.for_settings = first || new
    def self.ready? = current&.connected? || false

    def connected? = account_id.present? && access_token.present?

    # Why payment links can't be made, in words, or nil when they can.
    def blocker
      return "Stripe isn’t connected" unless connected?
      return "Stripe can’t send this install its events (#{last_error})" if webhook_endpoint_id.blank? && last_error.present?

      nil
    end

    def store_account!(access_token:, account_id:, livemode:)
      update!(access_token: access_token, account_id: account_id, livemode: livemode, connected_at: Time.current,
        oauth_state: nil, code_verifier: nil, last_error: nil)
    end

    def disconnect!
      update!(account_id: nil, account_name: nil, access_token: nil, webhook_endpoint_id: nil, webhook_secret: nil,
        connected_at: nil, oauth_state: nil, code_verifier: nil, last_error: nil)
    end

    def note_error!(message) = update_columns(last_error: message.to_s.truncate(500), updated_at: Time.current)

    # Stripe signs each delivery: "t=<time>,v1=<hmac>" over "<time>.<body>" with the endpoint's
    # secret. Old deliveries are refused so a captured one can't be replayed.
    def verify_signature(payload, header, tolerance: 5.minutes)
      return false if webhook_secret.blank? || header.blank?

      parts = header.split(",").map { it.split("=", 2) }
      timestamp = parts.find { it.first == "t" }&.last.to_i
      return false if timestamp.zero? || (Time.current.to_i - timestamp).abs > tolerance.to_i

      expected = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, "#{timestamp}.#{payload}")
      parts.select { it.first == "v1" }.any? { ActiveSupport::SecurityUtils.secure_compare(it.last.to_s, expected) }
    end

    private
      def ensure_singleton
        errors.add(:base, "Stripe is already set up") if Connection.exists?
      end
  end
end
